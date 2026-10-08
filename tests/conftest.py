# Pytest automatically discovers conftest.py: tests do not import fixtures manually.
# A test requests a fixture by putting its name in the function's arguments.
# Fixtures default to function scope, so every test case gets fresh setup.
import os
from dataclasses import dataclass
from datetime import datetime, timezone

# Application modules read these variables at import time, so set them first.
# These values belong only to this pytest process, not your Docker containers.
os.environ['DATABASE_URL'] = 'sqlite://'
os.environ['SECRET_KEY'] = 'test-key-test-key-test-key-test-key'
os.environ['ALGORITHM'] = 'HS256'
os.environ['ACCESS_TOKEN_EXPIRATION_MINUTES'] = '30'
os.environ['APP_ENV'] = 'test'

import pytest
from fastapi import FastAPI
from fastapi.testclient import TestClient
from sqlalchemy.pool import StaticPool
from sqlmodel import (
    Session,
    SQLModel,
    create_engine,
    select,
)

# Importing all table models registers them in SQLModel.metadata.
# create_all() needs that registry populated to know which tables to create.
import maxreps.backend.models 

from maxreps.backend.dependencies.db import get_session
from maxreps.backend.routes.user import router as user_router
from maxreps.backend.routes.exercise import router as exercise_router
from maxreps.backend.routes.lift_record import router as lift_record_router
from maxreps.backend.models.exercise import Exercise
from maxreps.backend.models.lift_record import LiftRecord
from maxreps.backend.models.user import User


@pytest.fixture
def session():
    # sqlite:// creates an in-memory database, separate from development Postgres.
    # TestClient runs requests in another thread. check_same_thread=False allows
    # that access; StaticPool keeps the same connection/database across threads.
    engine = create_engine(
        'sqlite://',
        connect_args={'check_same_thread': False},
        poolclass=StaticPool,
    )

    # Build tables from models. This does NOT test Alembic migrations or Postgres.
    SQLModel.metadata.create_all(engine)

    try:
        with Session(engine) as test_session:
            # Pytest passes this object to tests/fixtures requesting "session".
            # Execution pauses here until all dependents finish their test.
            yield test_session
    finally:
        # The finally block runs even when an assertion fails. Disposing the
        # engine discards the in-memory database, isolating the next test case.
        engine.dispose()


@pytest.fixture
def client(session):
    # Pytest resolves "session" first, then injects it into this fixture.
    # Use real routers, but omit Guard middleware so these tests focus on route
    # behavior. Rate limits, Redis integration, and production wiring need their
    # own tests. JWT authentication dependencies are still exercised here.
    app= FastAPI()
    app.include_router(user_router)
    app.include_router(exercise_router)
    app.include_router(lift_record_router)

    def override_get_session():
        # Replace only the database dependency, not authentication or handlers.
        yield session
    # The key is the original dependency function object, not its name string.
    app.dependency_overrides[get_session] = override_get_session
    try:
        with TestClient(app) as test_client:
            # Requests are sent through ASGI in-process; no server or Docker is
            # required. The context manager handles startup/shutdown and cleanup.
            yield test_client
    finally:
        app.dependency_overrides.clear()


@dataclass
class RegisteredAccount:
    # A dataclass groups related setup values into an object with named fields.
    # user is the database object; public is the registration response JSON.
    # Keep the plaintext test password only for constructing credential requests.
    user: User
    password: str
    public: dict

    @property
    def credentials(self):
        # OAuth2PasswordRequestForm expects "username", even though we use email.
        # @property lets tests read account.credentials without calling a method.
        return {"username": self.user.email, "password": self.password}


@pytest.fixture
def user_factory(client, session):
    """Register accounts through the API, including multiple users in one test."""
    def create(email="test@example.com", password="CorrectPassword123!"):
        # Factory fixture: return a callable so a test can create several accounts
        # with different emails. These calls still use the real registration API.
        response = client.post("/users", json={"email": email, "password": password})
        assert response.status_code == 201, response.text
        # .one() requires exactly one result; missing/duplicate setup fails early.
        user = session.exec(select(User).where(User.email == email)).one()
        return RegisteredAccount(user, password, response.json())

    return create


@pytest.fixture
def registered_user(user_factory):
    # Dependency chain: session -> client -> user_factory -> registered_user.
    # Within one test, pytest caches fixtures: requesting registered_user directly
    # and through auth_headers uses the SAME account, not two registrations.
    return user_factory()


@pytest.fixture
def auth_headers(client, registered_user):
    """Get a real login token; authentication is never overridden."""
    # data= sends form fields; json= would use the wrong login request format.
    response = client.post("/users/token", data=registered_user.credentials)
    assert response.status_code == 200, response.text
    return {"Authorization": f"Bearer {response.json()['access_token']}"}


@pytest.fixture
def exercise_factory(session):
    # Insert catalog data directly because there is no exercise-creation endpoint.
    # A returned factory permits several exercises in a filtering/list test.
    def create(name="Squat", category="strength", instructions=None):
        exercise = Exercise(
            name=name,
            category=category,
            instructions=instructions if instructions is not None else ["Bend knees", "Stand up"],
        )
        session.add(exercise)
        session.commit()
        # refresh() reloads persisted values, including the generated primary key.
        session.refresh(exercise)
        return exercise

    return create


@pytest.fixture
def exercise(exercise_factory):
    # Request this fixture when a test only needs one default exercise.
    return exercise_factory()


@pytest.fixture
def lift_factory(session, registered_user, exercise):
    """Arrange stored lifts for read tests; creation is tested separately through HTTP."""
    def create(user=None, exercise_id=None, attempted_at=None, **fields):
        # **fields collects optional overrides such as reps or weight_kg.
        # In the dictionary below, later entries overwrite earlier defaults.
        # Read tests arrange rows directly; POST tests independently prove that
        # the API constructs and persists records correctly.
        record = LiftRecord(
            user_id=user.id if user is not None else registered_user.user.id,
            exercise_id=exercise_id if exercise_id is not None else exercise.id,
            attempted_at=attempted_at if attempted_at is not None else datetime.now(timezone.utc),
            **{"weight_kg": 100.0, "reps": 1, "one_rep_max_est": 100.0, **fields},
        )
        session.add(record)
        session.commit()
        session.refresh(record)
        return record

    return create
