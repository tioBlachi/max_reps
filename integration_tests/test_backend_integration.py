import os
import time
from uuid import uuid4

import pytest
import requests
from alembic.config import Config
from alembic.migration import MigrationContext
from alembic.script import ScriptDirectory
from redis import Redis
from sqlalchemy import create_engine, inspect, text
from sqlalchemy.engine import make_url


# Running ordinary pytest locally should not require these external services.
# The workflow explicitly enables this suite after starting isolated services.
pytestmark = pytest.mark.skipif(
    os.getenv("RUN_INTEGRATION_TESTS") != "1",
    reason="Requires the isolated integration-test services",
)


@pytest.fixture(scope="session")
def db_engine():
    database_url = make_url(os.environ["DATABASE_URL"])

    # Catch accidentally pointing this suite at the development database.
    assert database_url.get_backend_name() == "postgresql"
    assert database_url.database == "maxreps_ci"

    engine = create_engine(database_url)

    try:
        yield engine
    finally:
        engine.dispose()


@pytest.fixture(scope="session")
def api(db_engine):
    # Depending on db_engine ensures its configuration checks run first.
    base_url = os.environ["API_BASE_URL"].rstrip("/")
    http = requests.Session()
    http.headers["User-Agent"] = "MaxReps-CI/1.0"

    try:
        # Starting Uvicorn in the workflow happens in the background.
        # Wait for application startup and admin creation to finish.
        for _ in range(60):
            try:
                response = http.get(
                    f"{base_url}/health",
                    timeout=2,
                )
                if response.status_code == 200:
                    break
            except requests.RequestException:
                pass

            time.sleep(1)
        else:
            pytest.fail(
                "The API did not become healthy. Check the workflow API logs."
            )

        def request(method, path, **kwargs):
            return http.request(
                method,
                f"{base_url}{path}",
                timeout=10,
                **kwargs,
            )

        yield request
    finally:
        http.close()


def test_migrations_and_startup(api, db_engine):
    # Compare the database's applied revisions with the migration files.
    # No revision ID is hardcoded, so adding a migration keeps this valid.
    scripts = ScriptDirectory.from_config(Config("alembic.ini"))

    with db_engine.connect() as connection:
        migration_context = MigrationContext.configure(connection)

        assert set(migration_context.get_current_heads()) == set(
            scripts.get_heads()
        )

        # Verify exercise seeding and application admin bootstrapping.
        exercise_count = connection.execute(
            text("SELECT COUNT(*) FROM exercise")
        ).scalar_one()

        admin_count = connection.execute(
            text("SELECT COUNT(*) FROM users WHERE is_admin IS TRUE")
        ).scalar_one()

        assert exercise_count > 0
        assert admin_count == 1

    # Inspect the schema PostgreSQL actually received from Alembic.
    schema = inspect(db_engine)

    indexes = schema.get_indexes("users")
    assert any(
        index["name"] == "uq_users_single_admin" and index["unique"]
        for index in indexes
    )

    foreign_keys = schema.get_foreign_keys("lift_records")
    assert any(
        foreign_key["referred_table"] == "users"
        and foreign_key["options"].get("ondelete") == "CASCADE"
        for foreign_key in foreign_keys
    )


def test_user_can_register_login_and_store_a_lift(api, db_engine):
    # A unique email avoids collisions if this test is repeated.
    email = f"ci-{uuid4().hex}@example.com"
    password = "IntegrationPassword123!"

    registration = api(
        "POST",
        "/users",
        json={"email": email, "password": password},
    )
    assert registration.status_code == 201, registration.text

    login = api(
        "POST",
        "/users/token",
        data={"username": email, "password": password},
    )
    assert login.status_code == 200, login.text

    token = login.json()["access_token"]
    headers = {"Authorization": f"Bearer {token}"}

    profile = api("GET", "/users/me", headers=headers)
    assert profile.status_code == 200, profile.text
    assert profile.json()["id"] == registration.json()["id"]

    with db_engine.connect() as connection:
        exercise_id = connection.execute(
            text("SELECT id FROM exercise ORDER BY id LIMIT 1")
        ).scalar_one()

    created = api(
        "POST",
        "/lift_record/",
        headers=headers,
        json={
            "exercise_id": exercise_id,
            "reps": 5,
            "weight": 100,
            "unit": "kg",
        },
    )
    assert created.status_code == 201, created.text

    record = created.json()
    assert record["one_rep_max_est"] == pytest.approx(116.67)

    # Fetch it again through a separate request to verify persistence.
    retrieved = api(
        "GET",
        f"/lift_record/{record['id']}",
        headers=headers,
        params={"unit": "kg"},
    )
    assert retrieved.status_code == 200, retrieved.text
    assert retrieved.json()["id"] == record["id"]
    assert retrieved.json()["user_id"] == profile.json()["id"]


def test_exercise_rate_limit_is_enforced_and_stored_in_redis(api):
    # The preceding tests do not request this particular endpoint.
    # Its configured limit is 60 requests per minute.
    for attempt in range(60):
        response = api("GET", "/exercises/")
        assert response.status_code == 200, (
            f"Request {attempt + 1}: "
            f"{response.status_code} {response.text}"
        )

    blocked = api("GET", "/exercises/")
    assert blocked.status_code == 429, blocked.text

    # A 429 alone would not establish that Redis was used.
    # Guard 8 stores its rate-limit windows as Redis sorted sets.
    redis_client = Redis.from_url(
        os.environ["REDIS_URL"],
        socket_connect_timeout=3,
        socket_timeout=3,
    )

    try:
        assert redis_client.ping()

        keys = list(
            redis_client.scan_iter(match="guard_core:rate_limit:*")
        )
        assert keys, "Guard did not create Redis rate-limit windows"

        assert any(
            redis_client.zcard(key) >= 60
            for key in keys
        ), "Redis did not record the exercise request window"
    finally:
        redis_client.close()