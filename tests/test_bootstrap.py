"""Admin creation at startup, without touching the development database."""

import pytest
from fastapi import FastAPI
from fastapi.testclient import TestClient
from sqlalchemy.exc import IntegrityError, SQLAlchemyError
from sqlmodel import Session, select

from maxreps.backend.dependencies.db import get_session
from maxreps.backend.models.user import User
from maxreps.backend.routes.admin import router as admin_router
from maxreps.backend.routes.user import router as user_router
from maxreps.services.bootstrap import ensure_admin_user
from maxreps.services.security import get_password_hash, verify_password


@pytest.fixture
def admin_environment(monkeypatch):
    # monkeypatch changes this pytest process only and restores each variable
    # afterwards. These example credentials never affect your Docker admin.
    credentials = {
        "email": "owner@example.com",
        "password": "OwnerPassword123!",
    }
    monkeypatch.setenv("ADMIN_EMAIL", credentials["email"])
    monkeypatch.setenv("ADMIN_PASSWORD", credentials["password"])
    return credentials


def test_bootstrap_creates_first_user_with_hashed_password(
    session, admin_environment, monkeypatch
):
    # Start with no users and provide mixed-case email/outer whitespace, just as
    # someone might type into .env. Bootstrap must normalize it like registration.
    monkeypatch.setenv("ADMIN_EMAIL", "  Owner@Example.COM  ")
    ensure_admin_user(session)

    # .one() fails if zero OR multiple users exist, proving this is the first user.
    admin = session.exec(select(User)).one()
    assert admin.email == admin_environment["email"]
    assert admin.is_admin is True
    assert admin.is_active is True
    assert admin.auth_version == 1
    assert admin.registered_at is not None
    assert admin.deactivated_at is None
    assert admin.reactivated_at is None
    assert admin.hashed_password != admin_environment["password"]
    assert verify_password(admin_environment["password"], admin.hashed_password)


def test_restart_preserves_existing_admin_account(
    session, admin_environment, monkeypatch
):
    ensure_admin_user(session)
    admin = session.exec(select(User)).one()
    original_id = admin.id
    original_registered_at = admin.registered_at

    # Simulate changes made after the initial startup. The initial environment
    # credentials are for creating an account, not for resetting it on restarts.
    admin.email = "changed@example.com"
    admin.hashed_password = get_password_hash("ChangedPassword123!")
    admin.auth_version += 1
    session.add(admin)
    session.commit()
    changed_hash = admin.hashed_password

    # Even different environment credentials must not create another admin or
    # overwrite the existing one's email, password hash, token version, or dates.
    monkeypatch.setenv("ADMIN_EMAIL", "different@example.com")
    monkeypatch.setenv("ADMIN_PASSWORD", "DifferentPassword123!")
    ensure_admin_user(session)
    session.expire_all()
    persisted = session.exec(select(User)).one()
    assert persisted.id == original_id
    assert persisted.email == "changed@example.com"
    assert persisted.hashed_password == changed_hash
    assert persisted.auth_version == 2
    assert persisted.registered_at == original_registered_at
    assert persisted.is_admin is True


def test_existing_admin_does_not_require_bootstrap_credentials(
    session, admin_user, monkeypatch
):
    # An admin manually created before this feature counts too. The check happens
    # before reading credentials, so you may remove bootstrap secrets afterwards.
    monkeypatch.delenv("ADMIN_EMAIL", raising=False)
    monkeypatch.delenv("ADMIN_PASSWORD", raising=False)
    ensure_admin_user(session)
    assert session.exec(select(User)).one().id == admin_user.user.id


def test_bootstrap_refuses_to_promote_existing_regular_user(
    session, registered_user, admin_environment, monkeypatch
):
    monkeypatch.setenv("ADMIN_EMAIL", registered_user.user.email)
    original_hash = registered_user.user.hashed_password
    original_version = registered_user.user.auth_version

    # A matching email alone must never grant admin access to a regular account.
    # Raising stops startup rather than continuing with an unexpected admin.
    with pytest.raises(RuntimeError, match="already belongs to a non-admin user"):
        ensure_admin_user(session)
    session.refresh(registered_user.user)
    assert registered_user.user.is_admin is False
    assert registered_user.user.hashed_password == original_hash
    assert registered_user.user.auth_version == original_version
    assert len(session.exec(select(User)).all()) == 1


@pytest.mark.parametrize("name", ["ADMIN_EMAIL", "ADMIN_PASSWORD"])
@pytest.mark.parametrize("value", [None, "", "   "], ids=["missing", "empty", "blank"])
def test_bootstrap_requires_credentials_when_no_admin_exists(
    session, admin_environment, monkeypatch, name, value
):
    # Two variables times three invalid values gives six isolated cases. None
    # means remove the variable entirely; empty/blank mean present but unusable.
    if value is None:
        monkeypatch.delenv(name)
    else:
        monkeypatch.setenv(name, value)
    with pytest.raises(RuntimeError, match=f"{name} must be configured"):
        ensure_admin_user(session)
    assert session.exec(select(User)).all() == []


@pytest.mark.parametrize("name,value", [
    ("ADMIN_EMAIL", "not-an-email"),
    ("ADMIN_PASSWORD", "short"),
    ("ADMIN_PASSWORD", "x" * 129),
])
def test_invalid_bootstrap_credentials_do_not_leak_passwords(
    session, admin_environment, monkeypatch, name, value
):
    monkeypatch.setenv(name, value)
    with pytest.raises(RuntimeError, match="must be a valid email address") as error:
        ensure_admin_user(session)
    # Pydantic's normal validation output includes the rejected input. The
    # startup error must give useful instructions without revealing a password.
    password = value if name == "ADMIN_PASSWORD" else admin_environment["password"]
    assert password not in str(error.value)
    assert error.value.__suppress_context__ is True
    assert session.exec(select(User)).all() == []


def test_bootstrap_accepts_admin_created_by_another_worker(
    session, admin_environment, monkeypatch
):
    original_commit = session.commit

    def competing_worker_commits_first():
        # Simulate the timing of two workers without threads: our bootstrap has
        # checked for an admin and prepared its insert, but another session wins
        # just before our commit. Our real commit then hits the unique index.
        with Session(session.get_bind()) as other_session:
            other_session.add(User(
                email=admin_environment["email"],
                hashed_password=get_password_hash(admin_environment["password"]),
                is_admin=True,
            ))
            other_session.commit()
        original_commit()

    monkeypatch.setattr(session, "commit", competing_worker_commits_first)
    ensure_admin_user(session)
    # The losing transaction was rolled back, so the session is usable and only
    # the other worker's account remains. This is not a threaded Postgres test.
    admin = session.exec(select(User)).one()
    assert admin.is_admin is True
    assert verify_password(admin_environment["password"], admin.hashed_password)


@pytest.mark.parametrize("error_type,expected_type,message", [
    (SQLAlchemyError, SQLAlchemyError, "simulated database failure"),
    (IntegrityError, RuntimeError, "database constraint"),
])
def test_bootstrap_rolls_back_database_failures(
    session, admin_environment, monkeypatch, error_type, expected_type, message
):
    def fail_commit():
        # Send the insert first, then fail before commit. A real rollback must
        # undo the insert; a call-count assertion alone could miss broken recovery.
        session.flush()
        if error_type is IntegrityError:
            raise IntegrityError("simulated insert", {}, Exception("constraint"))
        raise SQLAlchemyError("simulated database failure")

    monkeypatch.setattr(session, "commit", fail_commit)
    with pytest.raises(expected_type, match=message):
        ensure_admin_user(session)
    assert session.exec(select(User)).all() == []


def test_application_startup_creates_admin_before_requests(
    session, admin_environment, monkeypatch
):
    from maxreps.backend import main

    # Startup creates its own session, unlike route dependencies. Replace its
    # engine with this test's engine to keep it away from development Postgres.
    monkeypatch.setattr(main, "engine", session.get_bind())

    # Use the lifespan actually wired into the production app and real routers,
    # omitting Guard/Redis as in conftest.py. TestClient's with block runs startup.
    app = FastAPI(lifespan=main.app.router.lifespan_context)
    app.include_router(user_router)
    app.include_router(admin_router)

    def override_get_session():
        yield session

    app.dependency_overrides[get_session] = override_get_session
    with TestClient(app) as client:
        first_user = session.exec(select(User)).one()
        admin_id = first_user.id
        assert first_user.is_admin is True
        login = client.post("/users/token", data={
            "username": admin_environment["email"],
            "password": admin_environment["password"],
        })
        assert login.status_code == 200
        headers = {"Authorization": f"Bearer {login.json()['access_token']}"}
        assert client.get("/admin/stats", headers=headers).json() == {
            "total_users": 1, "active_users": 1, "inactive_users": 0,
        }

        # Registrations happen after startup and still create ordinary users.
        response = client.post("/users", json={
            "email": "later@example.com", "password": "LaterPassword123!",
        })
        assert response.status_code == 201
        later = session.exec(select(User).where(User.email == "later@example.com")).one()
        assert later.is_admin is False

    # Starting again against the same database must not duplicate the admin.
    with TestClient(app):
        assert len(session.exec(select(User)).all()) == 2
        assert session.exec(select(User).where(User.is_admin.is_(True))).one().id == admin_id


def test_missing_bootstrap_credentials_stop_startup(session, monkeypatch):
    from maxreps.backend import main

    monkeypatch.setattr(main, "engine", session.get_bind())
    monkeypatch.delenv("ADMIN_EMAIL", raising=False)
    monkeypatch.delenv("ADMIN_PASSWORD", raising=False)
    app = FastAPI(lifespan=main.app.router.lifespan_context)
    with pytest.raises(RuntimeError, match="ADMIN_EMAIL must be configured"):
        with TestClient(app):
            pytest.fail("Startup must fail before accepting requests without an admin")
    assert session.exec(select(User)).all() == []
