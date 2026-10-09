"""Admin permission, reporting, lifecycle, and deletion behavior.

Fixtures come from conftest.py. Each parameter case has a fresh SQLite database
with foreign keys enabled; Guard middleware and PostgreSQL migrations are tested
separately. Admin fixtures use real login tokens, not bypassed authentication.
"""

# How to read this file:
# - Functions starting with test_ are discovered and run by pytest.
# - Arguments such as client, session, and admin_headers are fixtures supplied
#   by name from conftest.py; you do not call those fixtures yourself.
# - A function-scoped fixture is created once per test case. When admin_headers
#   requests admin_user and the test also requests admin_user, both receive the
#   same account. The next test gets a new database and new accounts.
# - Parameterized arguments (method, path, headers, params, load_relationship)
#   instead receive values from their @pytest.mark.parametrize decorators.
# - Most tests follow Arrange -> Act -> Assert: prepare accounts, send a request,
#   then check the response and, when needed, the persisted database state.
# - An assertion failure stops that case, not the whole suite. Fixture cleanup
#   still runs, so failure in one test should not leave data in the next test.
#
# Fixtures used below:
# client: an in-process HTTP client for real FastAPI routes, without Guard.
# session: the isolated database session used by those requests and assertions.
# user_factory: a callable that registers accounts through POST /users.
# registered_user: one ordinary account created with that factory.
# auth_headers: a real token obtained by logging in as registered_user.
# admin_user: a separate account promoted in test setup, not through public API.
# admin_headers: a real login token for admin_user, issued after promotion.
# exercise/lift_factory: sample catalog data and a callable for arranging lifts.
# monkeypatch: pytest's tool for temporary replacements, undone after the test.
#
# Expected HTTP codes: 200 = success with data; 204 = success without a body;
# 401 = failed/missing authentication; 403 = authenticated but access forbidden;
# 404 = resource not found; 422 = request data fails validation.

from datetime import datetime, timezone
from uuid import uuid4

import pytest
from sqlalchemy.exc import IntegrityError, SQLAlchemyError
from sqlmodel import select

from maxreps.backend.models.exercise import Exercise
from maxreps.backend.models.lift_record import LiftRecord
from maxreps.backend.models.user import User


# Each tuple pairs an HTTP method with a URL. This reusable case table lets us
# apply the same permission expectations to every admin operation.
# uuid4() generates a valid UUID once when this module is imported. There is no
# matching row in the fresh test databases. Authentication/authorization should
# happen before the DELETE handler searches for that row, so unauthorized calls
# must return 401/403 rather than the handler's "User not found" 404.
ADMIN_ROUTES = [
    ("GET", "/admin/stats"),
    ("GET", "/admin/users"),
    ("DELETE", f"/admin/users/{uuid4()}"),
]


# Three routes times two header variants produces six independent cases.
# Stacked parametrize decorators generate the Cartesian product: every route
# is tested with every header variant. ids= gives readable names in pytest's
# output; it changes labels only, not how the test executes.
@pytest.mark.parametrize("method,path", ADMIN_ROUTES)
@pytest.mark.parametrize("headers", [{}, {"Authorization": "Bearer invalid-token"}],
                         ids=["missing-token", "invalid-token"])
def test_admin_routes_require_authentication(client, method, path, headers):
    # Arrange: no user/token fixtures are requested, so no account is logged in.
    # Act: client.request accepts a variable HTTP method, unlike client.get/delete.
    # Assert: absent or malformed bearer tokens are rejected before admin logic runs.
    assert client.request(method, path, headers=headers).status_code == 401


@pytest.mark.parametrize("method,path", ADMIN_ROUTES)
def test_regular_user_cannot_access_admin_routes(client, auth_headers, method, path):
    # Valid token, wrong role: reject even before looking up a deletion target.
    # auth_headers creates an ordinary account and logs it in before this body runs.
    # The token is valid, so this isolates require_admin rather than JWT decoding.
    # Three parametrize rows produce three tests, each checking one admin route.
    response = client.request(method, path, headers=auth_headers)
    assert response.status_code == 403
    assert response.json()["detail"] == "Not authorized for admin routes"


@pytest.mark.parametrize("method,path", ADMIN_ROUTES)
def test_inactive_admin_cannot_access_admin_routes(
    client, session, admin_user, admin_headers, method, path
):
    # Preserve the token version to isolate the active-account check.
    # admin_headers depends on admin_user, ensuring login occurs while it is active.
    # Now arrange an inactive admin directly in the test database. Keep the role and
    # auth_version unchanged: otherwise a version mismatch would give 401 first.
    # Direct setup intentionally bypasses the self-deactivation endpoint safeguard
    # to prove the dependency also rejects admins made inactive outside that route.
    admin_user.user.is_active = False
    session.add(admin_user.user)
    session.commit()
    response = client.request(method, path, headers=admin_headers)
    assert response.status_code == 403
    assert response.json()["detail"] == "Inactive User"


def test_admin_stats_when_only_admin_exists(client, admin_headers):
    # Requesting admin_headers creates exactly one active admin as fixture setup.
    # The grouped count query has no False group, which must default to zero.
    # Exact dictionary equality checks all response counts together.
    response = client.get("/admin/stats", headers=admin_headers)
    assert response.status_code == 200
    # An absent inactive group must be reported as zero, not cause a lookup error.
    assert response.json() == {"total_users": 1, "active_users": 1, "inactive_users": 0}


def test_admin_stats_includes_active_and_inactive_users(
    client, session, admin_headers, user_factory
):
    # Arrange two regular accounts in addition to the admin fixture.
    # user_factory returns RegisteredAccount; .user is the persisted User object.
    # Set one inactive and commit before the request so the query sees the change.
    # The total includes the admin: admin + active regular + inactive regular = 3.
    user_factory(email="active@example.com")
    inactive = user_factory(email="inactive@example.com")
    inactive.user.is_active = False
    session.add(inactive.user)
    session.commit()
    response = client.get("/admin/stats", headers=admin_headers)
    assert response.status_code == 200
    assert response.json() == {"total_users": 3, "active_users": 2, "inactive_users": 1}


def test_admin_user_list_paginates_filters_and_excludes_secrets(
    client, session, admin_headers, admin_user, user_factory
):
    # The admin fixture email is admin@example.com. Add aaa and zzz so the expected
    # alphabetical order is obvious and independent of randomly generated UUIDs.
    # Arrange a legacy inactive user with no known registration date and two known
    # lifecycle dates. This tests nullable timestamp serialization and field privacy.
    # Reuse this data to check the full list, pagination, both status filters, and
    # an offset beyond the end. These are related views of the same three accounts.
    first = user_factory(email="aaa@example.com")
    last = user_factory(email="zzz@example.com")
    last.user.is_active = False
    last.user.registered_at = None  # Legacy accounts can have unknown dates.
    last.user.deactivated_at = datetime(2026, 10, 1, tzinfo=timezone.utc)
    last.user.reactivated_at = datetime(2026, 9, 1, tzinfo=timezone.utc)
    session.add(last.user)
    session.commit()

    response = client.get("/admin/users", headers=admin_headers)
    assert response.status_code == 200
    body = response.json()
    assert (body["total"], body["offset"], body["limit"]) == (3, 0, 20)
    assert [row["email"] for row in body["users"]] == [
        first.user.email, admin_user.user.email, last.user.email,
    ]
    expected_fields = {"id", "email", "is_active", "is_admin", "registered_at",
                       "deactivated_at", "reactivated_at"}
    # Iterating a dict gives its keys, so set(row) is its field-name set.
    # all(...) must be true for EVERY result; exact key equality catches both
    # missing fields and accidental extras such as hashed_password/auth_version.
    assert all(set(row) == expected_fields for row in body["users"])
    assert body["users"][0]["registered_at"] is not None
    legacy = body["users"][-1]
    # [-1] selects the last list item: zzz@example.com after email sorting.
    assert legacy["registered_at"] is None
    assert legacy["is_active"] is False
    assert legacy["is_admin"] is False
    # JSON serializes datetimes as strings. fromisoformat() parses them back.
    # These arranged dates are already UTC. SQLite may omit their timezone when
    # reading them, so replace() attaches UTC for comparison; it does not shift
    # the clock time. This verifies the date value, not an exact JSON date format.
    assert datetime.fromisoformat(legacy["deactivated_at"]).replace(tzinfo=timezone.utc) == last.user.deactivated_at
    assert datetime.fromisoformat(legacy["reactivated_at"]).replace(tzinfo=timezone.utc) == last.user.reactivated_at

    # Total remains the number of matching users, not the page length.
    page = client.get("/admin/users", headers=admin_headers, params={"offset": 1, "limit": 1})
    assert page.status_code == 200
    assert page.json()["total"] == 3
    assert (page.json()["offset"], page.json()["limit"]) == (1, 1)
    assert [row["email"] for row in page.json()["users"]] == [admin_user.user.email]

    filtered = client.get("/admin/users", headers=admin_headers, params={"is_active": False})
    # params= sends URL query parameters, not a JSON body. FastAPI parses the
    # serialized boolean into the endpoint's optional bool argument.
    assert filtered.status_code == 200
    assert filtered.json()["total"] == 1
    assert [row["id"] for row in filtered.json()["users"]] == [str(last.user.id)]
    active = client.get("/admin/users", headers=admin_headers, params={"is_active": True})
    assert active.status_code == 200
    assert active.json()["total"] == 2
    assert all(row["is_active"] for row in active.json()["users"])

    empty = client.get("/admin/users", headers=admin_headers, params={"offset": 100})
    assert empty.status_code == 200
    assert empty.json()["total"] == 3
    assert empty.json()["users"] == []


@pytest.mark.parametrize("params", [
    {"offset": -1}, {"limit": 0}, {"limit": 101}, {"is_active": "invalid"},
])
def test_admin_user_list_invalid_query(client, admin_headers, params):
    # Four dictionaries produce four runs, each changing one query parameter.
    # offset must be >= 0; limit must be 1..100; is_active must parse as a boolean.
    # A real admin token keeps permission failure from hiding a validation problem.
    # 422 means FastAPI rejected the request parameters rather than running a valid query.
    assert client.get("/admin/users", headers=admin_headers, params=params).status_code == 422


# Loaded and unloaded relationships must both defer child deletion to the DB.
# This produces two separate runs, not two operations in the same database.
@pytest.mark.parametrize("load_relationship", [False, True], ids=["unloaded", "loaded"])
def test_admin_delete_cascades_only_target_lifts(
    client, session, admin_headers, registered_user, auth_headers,
    user_factory, exercise, lift_factory, load_relationship
):
    # Arrange three accounts: admin, target (registered_user), and another regular user.
    # auth_headers belongs to the target; admin_headers belongs to the separate admin.
    # lift_factory defaults to registered_user and the exercise fixture. Two calls
    # without overrides create target-owned lifts; user=other.user changes the owner.
    # Both owners use the same catalog exercise, which must survive account deletion.
    # This tests the real DELETE route plus SQLite foreign-key cascade enforcement,
    # not just removal of objects from a Python list. PostgreSQL still needs verification.
    target_id = registered_user.user.id
    other = user_factory(email="survivor@example.com")
    target_lifts = [lift_factory(), lift_factory()]
    survivor = lift_factory(user=other.user)
    target_lift_ids = {record.id for record in target_lifts}
    # Store scalar IDs BEFORE deletion: cached ORM objects can become stale or
    # fail to reload after their underlying rows have been deleted.
    survivor_id, other_id, exercise_id = survivor.id, other.user.id, exercise.id
    if load_relationship:
        # Accessing the relationship loads its children into SQLAlchemy's session.
        # With False, leave it unaccessed. passive_deletes="all" must work both ways.
        assert len(registered_user.user.lift_records) == 2

    response = client.delete(f"/admin/users/{target_id}", headers=admin_headers)
    assert response.status_code == 204
    assert response.content == b""
    # .content is raw bytes; b"" means an empty body. A 204 is not a JSON response.
    # Discard cached ORM values, then query persisted state after the DB cascade.
    session.expire_all()
    assert session.get(User, target_id) is None
    assert session.get(User, other_id) is not None
    remaining = session.exec(select(LiftRecord)).all()
    # Set comprehensions collect IDs without depending on database row order.
    assert {record.id for record in remaining} == {survivor_id}
    assert target_lift_ids.isdisjoint({record.id for record in remaining})
    # isdisjoint() means the two sets share no IDs: no deleted user's lift survives.
    assert session.get(Exercise, exercise_id) is not None
    assert client.get("/users/me", headers=auth_headers).status_code == 401
    # auth_headers still contains the deleted user's validly signed token. JWT
    # decoding alone is not enough: user lookup must now fail authentication.
    stats = client.get("/admin/stats", headers=admin_headers)
    assert stats.status_code == 200
    assert stats.json() == {"total_users": 2, "active_users": 2, "inactive_users": 0}


def test_regular_user_cannot_delete_existing_user(
    client, session, auth_headers, user_factory
):
    # Unlike the shared permission cases, this target really exists.
    # A normal account attempts deletion of another account; then query the database
    # to prove the 403 response came without the destructive side effect.
    target = user_factory(email="target@example.com")
    target_id = target.user.id
    response = client.delete(f"/admin/users/{target_id}", headers=auth_headers)
    assert response.status_code == 403
    session.expire_all()
    assert session.get(User, target_id) is not None


def test_admin_delete_missing_user(client, admin_headers):
    # Authenticate as admin so the handler runs instead of stopping at permissions.
    # A valid but nonexistent UUID should yield the handler's 404 error.
    response = client.delete(f"/admin/users/{uuid4()}", headers=admin_headers)
    assert response.status_code == 404
    assert response.json()["detail"] == "User not found"


def test_admin_delete_invalid_uuid(client, admin_headers):
    # Use valid admin authentication and malformed path data to isolate validation.
    # not-a-uuid cannot satisfy the UUID annotation, so expect 422 instead of 404.
    assert client.delete("/admin/users/not-a-uuid", headers=admin_headers).status_code == 422


def test_admin_cannot_delete_self(client, session, admin_user, admin_headers):
    # Send the admin's own ID using its real token. This target exists and the caller
    # has delete privileges; the explicit admin-account safeguard must reject it.
    # Verify the account remains and its token still accesses a protected admin route.
    user_id = admin_user.user.id
    response = client.delete(f"/admin/users/{user_id}", headers=admin_headers)
    assert response.status_code == 403
    assert response.json()["detail"] == "Admin accounts cannot be deleted"
    session.expire_all()
    assert session.get(User, user_id) is not None
    assert client.get("/admin/stats", headers=admin_headers).status_code == 200


def test_admin_cannot_deactivate_self(client, session, admin_user, admin_headers):
    # Provide the correct password so password verification succeeds first.
    # The admin safeguard must reject deactivation without changing status, date,
    # or auth_version. refresh() reloads persisted state into the existing object.
    # Finally prove the rejection did not revoke the token or lock the admin out.
    user = admin_user.user
    original_version = user.auth_version
    response = client.request(
        "DELETE", "/users/me/deactivate", headers=admin_headers,
        json={"current_password": admin_user.password},
    )
    assert response.status_code == 403
    assert response.json()["detail"] == "Admin accounts cannot be deactivated"
    session.refresh(user)
    assert user.is_active is True
    assert user.deactivated_at is None
    assert user.auth_version == original_version
    assert client.get("/admin/stats", headers=admin_headers).status_code == 200


def test_database_rejects_second_admin(session, admin_user, registered_user):
    # admin_user creates the first admin; registered_user creates a normal account.
    # Promote the latter directly to prove the unique partial index enforces the rule
    # even outside an HTTP endpoint. Failure should restore its non-admin state.
    registered_user.user.is_admin = True
    session.add(registered_user.user)
    # The database, not just the route, must enforce at most one admin.
    with pytest.raises(IntegrityError):
        session.commit()
    # pytest.raises makes the expected exception a PASS condition. No exception,
    # or the wrong exception type, would fail this test. After a failed flush/
    # commit, SQLAlchemy requires rollback before this session can be reused.
    session.rollback()
    session.refresh(registered_user.user)
    assert registered_user.user.is_admin is False
    assert session.exec(select(User).where(User.is_admin.is_(True))).one().id == admin_user.user.id
    # .is_(True) builds SQL's boolean predicate. .one() also requires exactly one
    # result, proving the original admin remains the only admin after rollback.


def test_registration_cannot_grant_admin_role(client, session):
    # Act as an unauthenticated registrant trying to submit is_admin=True.
    # The public request model excludes that field, and the route chooses its own
    # role default. The extra field is ignored, registration succeeds, and persisted
    # is_admin remains False. A successful response alone would not prove this.
    response = client.post("/users", json={
        "email": "injected@example.com", "password": "CorrectPassword123!", "is_admin": True,
    })
    assert response.status_code == 201
    user = session.exec(select(User).where(User.email == "injected@example.com")).one()
    assert user.is_admin is False


def test_failed_admin_delete_rolls_back(
    client, session, admin_headers, registered_user, lift_factory, monkeypatch
):
    # Arrange a regular user with one lift and save both IDs before deletion.
    # monkeypatch injects a database failure that is otherwise hard to reproduce.
    # The failure occurs AFTER deletion SQL and cascading child deletion have run
    # but BEFORE commit. A rollback must restore both rows as one transaction.
    # This checks actual recovery as well as whether the rollback method was called.
    # The test client raises unhandled exceptions instead of returning HTTP 500 by
    # default, so use pytest.raises rather than asserting a response status here.
    target_id = registered_user.user.id
    record_id = lift_factory().id
    original_rollback = session.rollback
    # Save the REAL bound method before replacing it. Calling session.rollback
    # from inside its replacement would recurse into itself forever.
    rollbacks = []

    def fail_commit():
        # Flush first so both the parent delete and database cascade happen,
        # then simulate failure. Rollback must restore both rows.
        session.flush()
        # flush() sends pending SQL inside the current transaction. It is not a
        # commit: these changes can still be undone. The database cascade runs
        # when that SQL deletes the parent, before we raise our simulated failure.
        raise SQLAlchemyError("simulated commit failure")

    def record_rollback():
        # This wrapper is a small "spy": record that rollback was called, then
        # perform the real rollback so we can check restored database rows.
        rollbacks.append(True)
        original_rollback()

    monkeypatch.setattr(session, "commit", fail_commit)
    # These replacements affect this session instance for this test only.
    # The route's database dependency returns that SAME session, so its commit()
    # invokes fail_commit(). Pytest restores patched methods during cleanup.
    monkeypatch.setattr(session, "rollback", record_rollback)
    # TestClient propagates unhandled server exceptions by default.
    with pytest.raises(SQLAlchemyError, match="simulated commit failure"):
        client.delete(f"/admin/users/{target_id}", headers=admin_headers)
    assert rollbacks == [True]
    # A list containing one item proves exactly one rollback call occurred here.
    session.expire_all()
    assert session.get(User, target_id) is not None
    assert session.get(LiftRecord, record_id) is not None
