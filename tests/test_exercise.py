# Pytest discovers test_*.py files and functions named test_*.
# Arguments such as client/session are fixtures from conftest.py, injected
# by name. Parametrized arguments instead come from the decorator rows.
# Tests arrange data, send HTTP requests, and assert responses/state.
# assert stops the test at the first failed expectation; other tests still run.

import pytest


def test_exercise_list_empty(client):
    # Request only client, without exercise fixtures: catalog starts empty.
    # An empty collection should be 200 with [], not a missing-resource 404.
    response = client.get("/exercises/")
    assert response.status_code == 200
    assert response.json() == []


def test_exercise_list_returns_public_summaries(client, exercise_factory):
    # Call the factory twice to arrange multiple catalog entries.
    # Key results by ID so the test does not assume an undocumented ordering.
    # Exact dictionaries also prove summaries exclude the instructions field.
    exercises = [exercise_factory(), exercise_factory(name="Bench press")]
    response = client.get("/exercises/")
    assert response.status_code == 200
    # The route promises no particular ordering.
    rows = {row["id"]: row for row in response.json()}
    assert set(rows) == {exercise.id for exercise in exercises}
    for exercise in exercises:
        assert rows[exercise.id] == {
            "id": exercise.id, "name": exercise.name, "category": exercise.category,
        }


def test_exercise_detail_includes_instructions(client, exercise):
    # The exercise fixture inserts one catalog entry and supplies its ID.
    # Unlike list summaries, detail responses should include instructions.
    # No auth_headers are supplied because exercise endpoints are public.
    response = client.get(f"/exercises/{exercise.id}")
    assert response.status_code == 200
    assert response.json() == {
        "id": exercise.id,
        "name": exercise.name,
        "category": exercise.category,
        "instructions": exercise.instructions,
    }


def test_exercise_not_found(client):
    # With no exercise fixture, ID 999 cannot exist in this fresh database.
    # Verify the handler returns its intended 404 and error message.
    response = client.get("/exercises/999")
    assert response.status_code == 404
    assert response.json()["detail"] == "Exercise not found"


# Each parametrize row becomes its own test, with fresh fixture setup.
# Parameter names match function arguments; pytest supplies their values.
@pytest.mark.parametrize("exercise_id", ["not-an-integer", "1.5"])
def test_exercise_invalid_id(client, exercise_id):
    # Two parameter values create two independent tests: nonnumeric text and a
    # fractional value. FastAPI rejects these as invalid integer path parameters
    # with 422 before an exercise database lookup can succeed.
    assert client.get(f"/exercises/{exercise_id}").status_code == 422
