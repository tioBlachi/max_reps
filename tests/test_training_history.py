"""History autocomplete must never expose another user's logged exercises."""
from datetime import datetime, timedelta, timezone

import pytest


@pytest.mark.parametrize('headers', [{}, {'Authorization': 'Bearer invalid'}])
def test_logged_exercises_requires_authentication(client, headers):
    assert client.get('/lift_record/exercises', headers=headers).status_code == 401


def test_logged_exercises_is_empty_for_a_new_user(client, auth_headers):
    response = client.get('/lift_record/exercises', headers=auth_headers)
    assert response.status_code == 200
    assert response.json() == []


def test_logged_exercises_is_unique_private_and_sorted_by_own_latest_attempt(
    client, auth_headers, user_factory, exercise_factory, lift_factory,
):
    first = exercise_factory(name='Bench press')
    second = exercise_factory(name='Deadlift')
    other_only = exercise_factory(name='Squat')
    exercise_factory(name='Never logged')
    other = user_factory(email='other@example.com')
    now = datetime(2026, 10, 21, tzinfo=timezone.utc)
    lift_factory(exercise_id=first.id, attempted_at=now)
    lift_factory(exercise_id=first.id, attempted_at=now - timedelta(days=1))
    lift_factory(exercise_id=second.id, attempted_at=now - timedelta(days=2))
    # This newer attempt belongs to someone else and must not change our order.
    lift_factory(user=other.user, exercise_id=second.id, attempted_at=now + timedelta(days=1))
    lift_factory(user=other.user, exercise_id=other_only.id, attempted_at=now)

    response = client.get('/lift_record/exercises', headers=auth_headers)
    assert response.status_code == 200
    assert response.json() == [
        {'id': first.id, 'name': first.name, 'category': first.category},
        {'id': second.id, 'name': second.name, 'category': second.category},
    ]


def test_training_history_returns_only_the_latest_five_matching_attempts(
    client, auth_headers, exercise, exercise_factory, lift_factory,
):
    now = datetime(2026, 10, 21, tzinfo=timezone.utc)
    records = [lift_factory(attempted_at=now - timedelta(days=index)) for index in range(7)]
    other_exercise = exercise_factory(name='Bench press')
    lift_factory(exercise_id=other_exercise.id, attempted_at=now + timedelta(days=1))
    response = client.get('/lift_record/', headers=auth_headers, params={
        'exercise_id': exercise.id, 'limit': 5, 'unit': 'kg',
    })
    assert response.status_code == 200
    assert [record['id'] for record in response.json()] == [str(record.id) for record in records[:5]]
    assert all(record['unit'] == 'kg' for record in response.json())


@pytest.mark.parametrize('path', ['/users/me/email', '/users/me/password'])
def test_browser_preflight_allows_profile_updates(path):
    from fastapi.testclient import TestClient
    from maxreps.backend.main import app

    # Outer CORS middleware handles OPTIONS before auth/Guard or the database.
    with_client = TestClient(app)
    try:
        response = with_client.options(path, headers={
            'Origin': 'http://localhost:3000',
            'Access-Control-Request-Method': 'PATCH',
            'Access-Control-Request-Headers': 'authorization,content-type',
        })
        assert response.status_code == 200
        assert 'PATCH' in response.headers['access-control-allow-methods']
    finally:
        with_client.close()
