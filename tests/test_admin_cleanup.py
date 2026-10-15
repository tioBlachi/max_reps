"""Exercise the real cleanup routes against an isolated database, never live data."""

from datetime import datetime, timedelta, timezone

import pytest
from sqlalchemy.exc import SQLAlchemyError
from sqlmodel import select

from maxreps.backend.models.exercise import Exercise
from maxreps.backend.models.lift_record import LiftRecord
from maxreps.backend.models.user import User
from maxreps.backend.routes import admin as admin_routes


PATH = '/admin/inactive-users/cleanup'
CUTOFF = datetime(2026, 7, 1, 12, tzinfo=timezone.utc)


@pytest.fixture
def fixed_cutoff(monkeypatch):
    # Freeze only this feature's clock. Exact-boundary cases then remain stable
    # regardless of when the suite runs or how long password hashing takes.
    monkeypatch.setattr(admin_routes, '_inactive_cleanup_cutoff', lambda: CUTOFF)
    return CUTOFF


@pytest.mark.parametrize('method', ['GET', 'DELETE'])
@pytest.mark.parametrize('headers', [{}, {'Authorization': 'Bearer invalid'}])
def test_cleanup_requires_authentication(client, method, headers):
    assert client.request(method, PATH, headers=headers).status_code == 401


@pytest.mark.parametrize('method', ['GET', 'DELETE'])
def test_cleanup_rejects_regular_users(client, auth_headers, method):
    response = client.request(method, PATH, headers=auth_headers)
    assert response.status_code == 403


@pytest.mark.parametrize('method', ['GET', 'DELETE'])
def test_cleanup_rejects_inactive_admins(client, session, admin_user, admin_headers, method):
    admin_user.user.is_active = False
    session.add(admin_user.user)
    session.commit()
    assert client.request(method, PATH, headers=admin_headers).status_code == 403


def test_cleanup_preview_and_delete_preserve_ineligible_users_and_cascade_lifts(
    client, session, admin_headers, admin_user, user_factory, lift_factory,
    exercise, fixed_cutoff,
):
    # Each tuple is (email prefix, currently active, latest deactivation date).
    # Exactly 90 days qualifies; even one microsecond more recent does not.
    cases = [
        ('old', False, CUTOFF - timedelta(days=10)),
        ('boundary', False, CUTOFF),
        ('recent', False, CUTOFF + timedelta(microseconds=1)),
        ('unknown', False, None),
        ('reactivated', True, CUTOFF - timedelta(days=30)),
    ]
    ids = {}
    lift_ids = {}
    for name, active, deactivated_at in cases:
        account = user_factory(email=f'{name}@example.com')
        account.user.is_active = active
        account.user.deactivated_at = deactivated_at
        session.add(account.user)
        session.commit()
        ids[name] = account.user.id
        lift_ids[name] = lift_factory(user=account.user).id
    admin_id, exercise_id = admin_user.user.id, exercise.id

    preview = client.get(PATH, headers=admin_headers)
    assert preview.status_code == 200
    assert preview.json()['eligible_users'] == 2
    # Preview is read-only: both target accounts and their lift records remain.
    assert session.get(User, ids['old']) is not None
    assert session.get(LiftRecord, lift_ids['old']) is not None

    response = client.request(
        'DELETE', PATH, headers=admin_headers,
        json={'cutoff_at': preview.json()['cutoff_at']},
    )
    assert response.status_code == 200
    assert response.json() == {'deleted_users': 2}
    session.expire_all()
    for name, _, _ in cases:
        should_survive = name not in {'old', 'boundary'}
        assert (session.get(User, ids[name]) is not None) == should_survive
        assert (session.get(LiftRecord, lift_ids[name]) is not None) == should_survive
    assert session.get(User, admin_id) is not None
    assert session.get(Exercise, exercise_id) is not None

    # Repeating the same operation has no additional destructive effect.
    again = client.request('DELETE', PATH, headers=admin_headers, json={'cutoff_at': CUTOFF.isoformat()})
    assert again.json() == {'deleted_users': 0}


def test_cleanup_rechecks_status_and_last_deactivation_after_preview(
    client, session, admin_headers, user_factory, fixed_cutoff,
):
    reactivated = user_factory(email='reactivated@example.com')
    deactivated_again = user_factory(email='new-deactivation@example.com')
    for account in [reactivated, deactivated_again]:
        account.user.is_active = False
        account.user.deactivated_at = CUTOFF - timedelta(days=1)
        session.add(account.user)
    session.commit()
    assert client.get(PATH, headers=admin_headers).json()['eligible_users'] == 2

    # Both accounts were eligible during preview. One reactivated; the other
    # reactivated and then deactivated again, restarting the 90-day period.
    reactivated.user.is_active = True
    deactivated_again.user.deactivated_at = CUTOFF + timedelta(days=80)
    session.add(reactivated.user)
    session.add(deactivated_again.user)
    session.commit()
    response = client.request('DELETE', PATH, headers=admin_headers, json={'cutoff_at': CUTOFF.isoformat()})
    assert response.json() == {'deleted_users': 0}
    assert len(session.exec(select(User)).all()) == 3


@pytest.mark.parametrize('body', [
    {}, {'cutoff_at': 'invalid'},
    {'cutoff_at': (CUTOFF + timedelta(seconds=1)).isoformat()},
])
def test_cleanup_rejects_missing_invalid_or_too_recent_cutoffs(client, admin_headers, fixed_cutoff, body):
    assert client.request('DELETE', PATH, headers=admin_headers, json=body).status_code == 422


def test_cleanup_rolls_back_if_commit_fails(
    client, session, admin_headers, user_factory, fixed_cutoff, monkeypatch,
):
    target = user_factory(email='rollback@example.com')
    target.user.is_active = False
    target.user.deactivated_at = CUTOFF
    session.add(target.user)
    session.commit()
    target_id = target.user.id

    def fail_commit():
        raise SQLAlchemyError('simulated commit failure')

    monkeypatch.setattr(session, 'commit', fail_commit)
    with pytest.raises(SQLAlchemyError):
        client.request('DELETE', PATH, headers=admin_headers, json={'cutoff_at': CUTOFF.isoformat()})
    # rollback() must restore the account even though DELETE had already run.
    session.expire_all()
    assert session.get(User, target_id) is not None


def test_profile_exposes_role_but_registration_cannot_grant_admin(client, auth_headers, admin_headers):
    assert client.get('/users/me', headers=auth_headers).json()['is_admin'] is False
    assert client.get('/users/me', headers=admin_headers).json()['is_admin'] is True
    response = client.post('/users', json={
        'email': 'cannot-promote@example.com', 'password': 'StrongPassword123!', 'is_admin': True,
    })
    assert response.status_code == 201
    assert response.json()['is_admin'] is False


@pytest.mark.parametrize('path', ['/users/me/deactivate', PATH])
def test_browser_preflight_allows_authenticated_delete(path):
    from fastapi.testclient import TestClient
    from maxreps.backend.main import app

    # OPTIONS is handled by outer CORS middleware. No lifespan, live database,
    # bootstrap account, or Guard/Redis calls are needed for this browser check.
    client = TestClient(app)
    try:
        response = client.options(path, headers={
            'Origin': 'http://localhost:3000',
            'Access-Control-Request-Method': 'DELETE',
            'Access-Control-Request-Headers': 'authorization,content-type',
        })
        assert response.status_code == 200
        assert response.headers['access-control-allow-origin'] == 'http://localhost:3000'
        assert 'DELETE' in response.headers['access-control-allow-methods']
    finally:
        client.close()
