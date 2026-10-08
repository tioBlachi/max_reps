# Pytest discovers test_*.py files and functions named test_*.
# Arguments such as client/session are fixtures from conftest.py, injected
# by name. Parametrized arguments instead come from the decorator rows.
# Tests arrange data, send HTTP requests, and assert responses/state.
# assert stops the test at the first failed expectation; other tests still run.

from datetime import datetime, timezone
from uuid import UUID, uuid4

import pytest
from sqlmodel import select

from maxreps.backend.models.lift_record import LiftRecord


def as_utc(value):
    # Normalize response/database timestamps for comparisons in these tests.
    # SQLite can omit timezone information when reading datetimes; this helper
    # compares the UTC instant, not whether JSON retains an explicit Z suffix.
    # PostgreSQL timezone behavior needs its own integration tests.
    timestamp = datetime.fromisoformat(value)
    if timestamp.utcoffset() is None:
        return timestamp.replace(tzinfo=timezone.utc)
    return timestamp.astimezone(timezone.utc)


# Each parametrize row becomes its own test, with fresh fixture setup.
# Parameter names match function arguments; pytest supplies their values.
@pytest.mark.parametrize(
    "unit,weight,reps,stored_weight,stored_max,response_max",
    [
        ("kg", 80, 5, 80, 93.33, 93.33),
        ("lb", 100, 5, 45.35923700083526, 52.92, 116.67),
        ("kg", 80, 1, 80, 80, 80),
        ("lb", 100, 1, 45.35923700083526, 45.36, 100),
    ],
)
def test_create_lift_converts_and_persists(
    client, session, registered_user, auth_headers, exercise,
    unit, weight, reps, stored_weight, stored_max, response_max,
):
    # Each tuple supplies six named parameters, producing four independent cases:
    # lb/kg inputs with one rep or five reps. Expected numbers are explicit,
    # rather than computed by the application helpers we are trying to test.
    # Check both stored kilograms and the response in the submitted unit.
    # pytest.approx tolerates floating-point representation differences.
    response = client.post(
        "/lift_record/", headers=auth_headers,
        json={"exercise_id": exercise.id, "weight": weight, "reps": reps, "unit": unit},
    )
    assert response.status_code == 201
    body = response.json()
    record = session.get(LiftRecord, UUID(body["id"]))
    assert record is not None
    assert record.user_id == registered_user.user.id
    assert record.exercise_id == exercise.id
    assert record.reps == reps
    assert record.weight_kg == pytest.approx(stored_weight)
    assert record.one_rep_max_est == pytest.approx(stored_max)
    assert body["user_id"] == registered_user.public["id"]
    assert body["exercise_id"] == exercise.id
    assert body["reps"] == reps
    assert body["unit"] == unit
    assert body["weight"] == pytest.approx(weight)
    assert body["one_rep_max_est"] == response_max
    assert "weight_kg" not in body


def test_create_lift_defaults_to_pounds_and_current_time(client, auth_headers, exercise):
    # Omit unit and attempted_at to test defaults. Capture times on either side
    # of the request instead of assuming it occurs at an exact frozen instant.
    before = datetime.now(timezone.utc)
    response = client.post(
        "/lift_record/", headers=auth_headers,
        json={"exercise_id": exercise.id, "weight": 100, "reps": 5},
    )
    after = datetime.now(timezone.utc)
    assert response.status_code == 201
    assert response.json()["unit"] == "lb"
    assert before <= as_utc(response.json()["attempted_at"]) <= after


# Each parametrize row becomes its own test, with fresh fixture setup.
# Parameter names match function arguments; pytest supplies their values.
@pytest.mark.parametrize(
    "timestamp",
    ["2026-10-01T12:00:00", "2026-10-01T12:00:00Z", "2026-10-01T08:00:00-04:00"],
)
def test_create_lift_normalizes_timestamp(client, session, auth_headers, exercise, timestamp):
    # Three parameter values represent the same expected UTC instant: naive
    # (interpreted as UTC), explicit UTC, and a negative four-hour offset.
    # Check response and persistence; this proves normalization, not formatting.
    response = client.post(
        "/lift_record/", headers=auth_headers,
        json={"exercise_id": exercise.id, "weight": 80, "reps": 5,
              "unit": "kg", "attempted_at": timestamp},
    )
    assert response.status_code == 201
    expected = datetime(2026, 10, 1, 12, tzinfo=timezone.utc)
    assert as_utc(response.json()["attempted_at"]) == expected
    record = session.get(LiftRecord, UUID(response.json()["id"]))
    assert as_utc(record.attempted_at.isoformat()) == expected


def test_create_lift_missing_exercise(client, session, auth_headers):
    # Valid credentials but no matching exercise should yield 404.
    # The empty-table assertion proves the rejected request saved no lift.
    response = client.post(
        "/lift_record/", headers=auth_headers,
        json={"exercise_id": 999, "weight": 80, "reps": 5},
    )
    assert response.status_code == 404
    assert response.json()["detail"] == "Exercise with id: 999 not found"
    assert session.exec(select(LiftRecord)).all() == []


# Each parametrize row becomes its own test, with fresh fixture setup.
# Parameter names match function arguments; pytest supplies their values.
@pytest.mark.parametrize(
    "invalid_fields",
    [{"weight": 0}, {"weight": -1}, {"reps": 0}, {"reps": -1},
     {"unit": "oz"}, {"attempted_at": "invalid-date"}],
)
def test_create_lift_invalid_input(client, session, auth_headers, exercise, invalid_fields):
    # Each dictionary replaces one otherwise-valid field using **invalid_fields.
    # Six separate cases cover weight/reps boundaries, unit, and timestamp.
    # 422 is request validation failure; no database write should occur.
    response = client.post(
        "/lift_record/", headers=auth_headers,
        json={"exercise_id": exercise.id, "weight": 80, "reps": 5, **invalid_fields},
    )
    assert response.status_code == 422
    assert session.exec(select(LiftRecord)).all() == []


def test_create_lift_cannot_assign_another_owner(
    client, registered_user, auth_headers, exercise, user_factory, session
):
    # Attempt to inject another account ID into the JSON request.
    # Ownership must come from the authenticated user, not client input.
    # Check the returned owner and the actual persisted owner independently.
    other = user_factory(email="other@example.com")
    response = client.post(
        "/lift_record/", headers=auth_headers,
        json={"exercise_id": exercise.id, "weight": 80, "reps": 5,
              "user_id": str(other.user.id)},
    )
    assert response.status_code == 201
    assert response.json()["user_id"] == registered_user.public["id"]
    assert session.get(LiftRecord, UUID(response.json()["id"])).user_id == registered_user.user.id


# Each parametrize row becomes its own test, with fresh fixture setup.
# Parameter names match function arguments; pytest supplies their values.
@pytest.mark.parametrize("method,path", [
    ("POST", "/lift_record/"), ("GET", "/lift_record/"),
    ("GET", f"/lift_record/{UUID(int=1)}"),
])
@pytest.mark.parametrize("headers", [{}, {"Authorization": "Bearer invalid-token"}],
                         ids=["missing-token", "invalid-token"])
def test_lift_routes_require_authentication(client, exercise, method, path, headers):
    # Stacked parametrize decorators create every combination: three routes
    # times two header variants = SIX tests, each with fresh fixtures.
    # ids= labels the header variants in pytest output to identify failures.
    # The conditional **dictionary adds a JSON body only for POST requests.
    # Use a valid UUID for detail so malformed input cannot obscure auth checks.
    response = client.request(
        method, path, headers=headers,
        **({"json": {"exercise_id": exercise.id, "weight": 80, "reps": 5}}
           if method == "POST" else {}),
    )
    assert response.status_code == 401


# Each parametrize row becomes its own test, with fresh fixture setup.
# Parameter names match function arguments; pytest supplies their values.
@pytest.mark.parametrize("method,path", [
    ("POST", "/lift_record/"), ("GET", "/lift_record/"),
    ("GET", f"/lift_record/{UUID(int=1)}"),
])
def test_inactive_user_cannot_access_lifts(
    client, session, registered_user, auth_headers, exercise, method, path
):
    # Keep the version unchanged to isolate the active-account dependency.
    # Run once per lift route with a valid token for an inactive account.
    # Do not increment auth_version here: that would cause 401 at version
    # validation instead of exercising the active-account check returning 403.
    registered_user.user.is_active = False
    session.add(registered_user.user)
    session.commit()
    response = client.request(
        method, path, headers=auth_headers,
        **({"json": {"exercise_id": exercise.id, "weight": 80, "reps": 5}}
           if method == "POST" else {}),
    )
    assert response.status_code == 403
    assert response.json()["detail"] == "Inactive User"


def test_lift_history_empty(client, auth_headers):
    # Authenticate without requesting lift_factory: this user has no records.
    # Return an empty successful collection, not a missing-resource error.
    response = client.get("/lift_record/", headers=auth_headers)
    assert response.status_code == 200
    assert response.json() == []


def test_lift_history_filters_owner_exercise_and_paginates(
    client, auth_headers, lift_factory, exercise, exercise_factory, user_factory
):
    # Arrange known timestamps, two exercises, and a foreign-owned newest lift.
    # Read factories insert rows directly so this test focuses on query behavior.
    # Check ordering/ownership first, then exercise filtering and pagination.
    # offset=1 skips the newest visible row; limit=1 returns only the next row.
    old = lift_factory(attempted_at=datetime(2026, 10, 1, tzinfo=timezone.utc))
    latest = lift_factory(attempted_at=datetime(2026, 10, 3, tzinfo=timezone.utc))
    other_exercise = exercise_factory(name="Bench press")
    middle = lift_factory(exercise_id=other_exercise.id,
                          attempted_at=datetime(2026, 10, 2, tzinfo=timezone.utc))
    other = user_factory(email="other@example.com")
    foreign = lift_factory(user=other.user,
                           attempted_at=datetime(2026, 10, 4, tzinfo=timezone.utc))

    response = client.get("/lift_record/", headers=auth_headers)
    assert response.status_code == 200
    assert [row["id"] for row in response.json()] == [str(latest.id), str(middle.id), str(old.id)]
    assert all(row["id"] != str(foreign.id) for row in response.json())

    filtered = client.get("/lift_record/", headers=auth_headers,
                          params={"exercise_id": exercise.id})
    assert filtered.status_code == 200
    assert [row["id"] for row in filtered.json()] == [str(latest.id), str(old.id)]
    page = client.get("/lift_record/", headers=auth_headers, params={"offset": 1, "limit": 1})
    assert page.status_code == 200
    assert [row["id"] for row in page.json()] == [str(middle.id)]
    empty = client.get("/lift_record/", headers=auth_headers, params={"exercise_id": 999})
    assert empty.status_code == 200
    assert empty.json() == []


def test_lift_history_orders_timestamp_ties_by_id(client, auth_headers, lift_factory):
    # Create equal timestamps to force the query to use its secondary ID sort.
    # Expected ordering is deterministic even though UUID generation is random.
    timestamp = datetime(2026, 10, 1, tzinfo=timezone.utc)
    records = [lift_factory(attempted_at=timestamp) for _ in range(3)]
    response = client.get("/lift_record/", headers=auth_headers)
    assert response.status_code == 200
    assert [row["id"] for row in response.json()] == sorted(
        [str(record.id) for record in records], reverse=True
    )


# Each parametrize row becomes its own test, with fresh fixture setup.
# Parameter names match function arguments; pytest supplies their values.
@pytest.mark.parametrize("params", [
    {"offset": -1}, {"limit": 0}, {"limit": 101}, {"exercise_id": 0}, {"unit": "oz"},
])
def test_lift_history_invalid_query(client, auth_headers, params):
    # Each parameter dictionary supplies an invalid query value for one run.
    # Boundary cases exercise offset >= 0, limit 1..100, and exercise_id > 0.
    assert client.get("/lift_record/", headers=auth_headers, params=params).status_code == 422


# Each parametrize row becomes its own test, with fresh fixture setup.
# Parameter names match function arguments; pytest supplies their values.
@pytest.mark.parametrize("unit,expected_weight", [("kg", 100), ("lb", 220.46226218)])
def test_lift_reads_convert_units(client, auth_headers, lift_factory, unit, expected_weight):
    # Seed a 100 kg single-rep record, then request kg and lb in separate cases.
    # History and detail must serialize the SAME record consistently.
    # Weight conversion uses approximate equality; the rounded estimate uses
    # the expected two-decimal number. JSON numbers need not retain trailing zeros.
    record = lift_factory()
    detail = client.get(f"/lift_record/{record.id}", headers=auth_headers, params={"unit": unit})
    history = client.get("/lift_record/", headers=auth_headers, params={"unit": unit})
    assert detail.status_code == history.status_code == 200
    assert history.json() == [detail.json()]
    assert detail.json()["weight"] == pytest.approx(expected_weight)
    assert detail.json()["one_rep_max_est"] == round(expected_weight, 2)
    assert detail.json()["unit"] == unit
    assert detail.json()["id"] == str(record.id)


def test_lift_detail_defaults_to_pounds(client, auth_headers, lift_factory):
    # Omit the unit query parameter and verify the read default is pounds.
    record = lift_factory()
    response = client.get(f"/lift_record/{record.id}", headers=auth_headers)
    assert response.status_code == 200
    assert response.json()["unit"] == "lb"
    assert response.json()["weight"] == pytest.approx(220.46226218)


def test_lift_detail_missing_or_other_owner_returns_same_404(
    client, auth_headers, lift_factory, user_factory
):
    # Compare a foreign-owned record with a random missing UUID.
    # Identical 404 responses avoid revealing another user's record existence.
    other = user_factory(email="other@example.com")
    foreign = lift_factory(user=other.user)
    responses = [client.get(f"/lift_record/{record_id}", headers=auth_headers)
                 for record_id in (foreign.id, uuid4())]
    assert all(response.status_code == 404 for response in responses)
    assert responses[0].json() == responses[1].json() == {"detail": "Lift record not found"}


def test_lift_detail_invalid_uuid(client, auth_headers):
    # Authenticate normally, then supply malformed UUID text to isolate the
    # path validation error (422) from authentication and ownership checks.
    assert client.get("/lift_record/not-a-uuid", headers=auth_headers).status_code == 422
