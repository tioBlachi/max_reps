# Pytest discovers test_*.py files and functions named test_*.
# Arguments such as client/session are fixtures from conftest.py, injected
# by name. Parametrized arguments instead come from the decorator rows.
# Tests arrange data, send HTTP requests, and assert responses/state.
# assert stops the test at the first failed expectation; other tests still run.

from sqlmodel import select
import pytest

from maxreps.backend.models.user import User
from maxreps.services.security import verify_password


# Each parametrize row becomes its own test, with fresh fixture setup.
# Parameter names match function arguments; pytest supplies their values.
@pytest.mark.parametrize(
    "method,path,extra_fields",
    [
        ("PATCH", "/users/me/password", {"new_password": "NewPassword456!"}),
        ("DELETE", "/users/me/deactivate", {}),
    ],
)
def test_wrong_current_password_leaves_account_unchanged(client, session, registered_user, auth_headers, method, path, extra_fields):
    # Each parameter row selects a different sensitive operation, but the same
    # security rule applies: a wrong current password must leave all state intact.
    # Fixture arguments are supplied by pytest; method/path/extra_fields come
    # from parametrize. **extra_fields adds new_password only for PATCH.
    email = registered_user.user.email
    headers = auth_headers

    user = session.exec(select(User).where(User.email == email)).one()
    original_hash = user.hashed_password
    original_version = user.auth_version

    response = client.request(
        method,
        path,
        headers=headers,
        json={"current_password": "WrongPassword123!", **extra_fields},
    )

    assert response.status_code == 403
    assert response.json()["detail"] == "Current password is incorrect"

    session.refresh(user)
    assert user.hashed_password == original_hash
    assert user.is_active is True
    assert user.auth_version == original_version
    # A rejected account change must not revoke the current session.
    assert client.get("/users/me", headers=headers).status_code == 200


def test_email_change_conflict_leaves_both_accounts_unchanged(
    client, session, registered_user, auth_headers, user_factory
):
    # Use user_factory to create a second account in the SAME isolated database.
    # Snapshot immutable field values before the request; storing only references
    # to User objects would not preserve their old values if they changed.
    # zip() pairs each account with its snapshot for the unchanged-state checks.
    other = user_factory(email="existing@example.com")
    password = registered_user.password
    emails = (registered_user.user.email, other.user.email)
    users = [registered_user.user, other.user]
    original_states = [
        (user.email, user.hashed_password, user.is_active, user.auth_version)
        for user in users
    ]
    headers = auth_headers

    response = client.patch(
        "/users/me/email",
        headers=headers,
        json={"current_password": password, "email": emails[1]},
    )

    assert response.status_code == 409
    assert response.json()["detail"] == (
        "Another user is already registered with this email"
    )
    for user, original_state in zip(users, original_states):
        session.refresh(user)
        assert (
            user.email, user.hashed_password, user.is_active, user.auth_version
        ) == original_state

    profile_response = client.get("/users/me", headers=headers)
    assert profile_response.status_code == 200
    assert profile_response.json()["email"] == emails[0]


def test_register_user(client, session):
    # Valid registration
    # Arrange valid JSON, act through the registration endpoint, then assert
    # both the public response and database state. This test deliberately creates
    # its own account because registration itself is the behavior under test.
    # verify_password checks the hash without expecting a fixed, salted hash.
    password = 'testpassword123!'
    payload = {
        'email': 'newuser@example.com',
        'password': password,
    }

    response = client.post('/users', json=payload)

    assert response.status_code == 201

    body = response.json()

    assert body['email'] == payload['email']
    assert 'id' in body
    assert 'password' not in body
    assert 'hashed_password' not in body

    user = session.exec(
        select(User).where(User.email == payload['email'])
    ).first()

    assert user is not None
    assert str(user.id) == body['id']
    assert user.is_active is True
    assert user.hashed_password != password
    assert verify_password(password, user.hashed_password)


def test_duplicate_email_registration(client, session, registered_user):
    # registered_user has already created the first account through the API.
    # Resubmit that email and check both the 409 response and database row count.
    payload = {"email": registered_user.user.email, "password": registered_user.password}
    second_response = client.post("/users", json=payload)

    assert second_response.status_code == 409
    assert second_response.json()['detail'] == "User already exists with that email address"

    users = session.exec(
        select(User).where(User.email == payload['email'])
    ).all()

    assert len(users) == 1


def test_successful_login(client, registered_user):
    # Login uses data= for form fields, not json=. Email goes in username.
    # A token in the response is not enough: use it to read the correct profile.
    # Bearer headers exercise the real JWT validation/auth_version dependencies.
    payload = {"email": registered_user.user.email, "password": registered_user.password}

    login_response = client.post(
        '/users/token',
        data = {
            'username': payload['email'],
            'password' : payload['password']
        },
    )

    assert login_response.status_code == 200

    token_data = login_response.json()
    assert token_data['token_type'] == 'bearer'
    assert token_data['access_token'] # exists

    # Check that get /users/me is working
    profile_response = client.get(
        '/users/me',
        headers = {
            "Authorization": f'Bearer {token_data['access_token']}',
        },
    )

    assert profile_response.status_code == 200

    profile = profile_response.json()
    assert profile['email'] == payload['email']
    assert profile['id'] == registered_user.public['id']
    assert 'hashed_password' not in profile


# Each parametrize row becomes its own test, with fresh fixture setup.
# Parameter names match function arguments; pytest supplies their values.
@pytest.mark.parametrize(
    'username,password',
    [
        ('test@example.com', 'WrongPassword123!'),
        ('unknown@example.com', 'CorrectPassword123!')
    ]
)
def test_login_invalid_credentials(client, registered_user, username, password):
    # Parametrize runs this twice: an existing account with a wrong password,
    # then an unknown account. registered_user is intentionally requested even
    # though not referenced below: its setup creates test@example.com first.
    # Both cases should look identical to the caller and must not issue a token.
    response = client.post(
        '/users/token',
        data={
            'username': username,
            'password': password,
        },
    )

    assert response.status_code == 401
    assert response.json()['detail'] == 'Could not validate credentials'
    assert response.headers['WWW-Authenticate'] == 'Bearer'
    assert 'access_token' not in response.json()


def test_deactivation_blocks_login_and_invalidates_token(client, session, registered_user, auth_headers):
    # auth_headers logs in the SAME registered_user requested by this test.
    # Save the original version before deactivation. Check persisted state,
    # rejection of the old token (401), and rejection of fresh login (403).
    # 204 means success with no response body, so do not call response.json().
    payload = {"email": registered_user.user.email, "password": registered_user.password}
    headers = auth_headers

    profile_response = client.get('/users/me', headers=headers)
    assert profile_response.status_code == 200

    user = registered_user.user
    original_version = user.auth_version

    # DELETE (Deactivate the user)
    deactivate_response = client.request(
        'DELETE',
        '/users/me/deactivate',
        headers=headers,
        json={'current_password' : payload['password']}
    )

    assert deactivate_response.status_code == 204
    assert deactivate_response.content == b""

    # Verify the auth_version has been incremented
    session.refresh(user) # just to be explicit
    assert user.is_active is False
    assert user.auth_version == original_version + 1

    old_token_response = client.get("/users/me", headers=headers)
    assert old_token_response.status_code == 401

    # Making sure that even with correct credentials, user cannot log in to an inactive account
    inactive_login_response = client.post(
        '/users/token',
        data={
            'username': payload['email'],
            'password' : payload['password']
        },
    )

    assert inactive_login_response.status_code == 403
    assert inactive_login_response.json()['detail'] == "Inactive user"
    assert 'access_token' not in inactive_login_response.json()


def test_reactivation_issues_new_token_and_keeps_old_token_invalid(client, session, registered_user, auth_headers):
    # Exercise the full lifecycle through HTTP: deactivate, reactivate, read.
    # Retain old_headers to prove reactivation does not revive revoked tokens.
    # Deactivation already increments auth_version; reactivation should keep it.
    payload = {"email": registered_user.user.email, "password": registered_user.password}
    credentials = registered_user.credentials
    old_headers = auth_headers

    deactivate_response = client.request(
        "DELETE",
        "/users/me/deactivate",
        headers=old_headers,
        json={"current_password": payload["password"]},
    )
    assert deactivate_response.status_code == 204

    user = registered_user.user
    session.refresh(user)
    assert user.is_active is False
    deactivated_version = user.auth_version

    # Reactivation uses credentials, without a bearer token.
    reactivate_response = client.post(
        "/users/reactivate",
        data=credentials,
    )
    assert reactivate_response.status_code == 200

    token_data = reactivate_response.json()
    assert token_data["token_type"] == "bearer"
    assert token_data["access_token"]

    session.refresh(user)
    assert user.is_active is True
    assert user.auth_version == deactivated_version

    # The new token must work for the correct account.
    new_headers = {
        "Authorization": f"Bearer {token_data['access_token']}",
    }
    profile_response = client.get("/users/me", headers=new_headers)

    assert profile_response.status_code == 200
    assert profile_response.json()["id"] == registered_user.public["id"]
    assert profile_response.json()["email"] == payload["email"]

    # Reactivation must not restore access for the old token.
    old_token_response = client.get("/users/me", headers=old_headers)
    assert old_token_response.status_code == 401

    # Normal login should work again.
    active_login_response = client.post("/users/token", data=credentials)
    assert active_login_response.status_code == 200


def test_reactivation_wrong_password_keeps_account_inactive(client, session, registered_user):
    # Arrange inactivity directly in the database for this focused rejection test.
    # The separate lifecycle test already proves deactivation through HTTP.
    # refresh() reloads database values after the request, so assertions inspect
    # persisted state rather than assuming the earlier Python object is current.
    payload = {"email": registered_user.user.email, "password": registered_user.password}

    user = registered_user.user

    user.is_active = False
    user.auth_version += 1
    session.add(user)
    session.commit()
    original_version = user.auth_version

    # Attempt reactivation with the wrong password.
    response = client.post(
        "/users/reactivate",
        data={
            "username": payload["email"],
            "password": "WrongPassword123!",
        },
    )

    assert response.status_code == 401
    assert response.json()["detail"] == "Could not validate credentials"
    assert response.headers["WWW-Authenticate"] == "Bearer"
    assert "access_token" not in response.json()

    # Failed authentication must not change the account.
    session.refresh(user)
    assert user.is_active is False
    assert user.auth_version == original_version


def test_reactivation_unknown_email(client, session):
    # No registered_user fixture: the database intentionally contains no account.
    # Verify graceful 401 handling and that failure does not create a user.
    email = "unknown@example.com"

    response = client.post(
        "/users/reactivate",
        data={
            "username": email,
            "password": "TestPassword123!",
        },
    )

    assert response.status_code == 401
    assert response.json()["detail"] == "Could not validate credentials"
    assert response.headers["WWW-Authenticate"] == "Bearer"
    assert "access_token" not in response.json()

    user = session.exec(
        select(User).where(User.email == email)
    ).first()

    assert user is None


def test_reactivation_already_active_account(client, session, registered_user):
    # Send correct credentials for an active account: expect a conflict, not a
    # token. This prevents reactivation being used as an alternative login route.
    payload = {"email": registered_user.user.email, "password": registered_user.password}

    user = registered_user.user
    original_version = user.auth_version
    assert user.is_active is True

    # Valid credentials, but the account does not need reactivation.
    response = client.post(
        "/users/reactivate",
        data={
            "username": payload["email"],
            "password": payload["password"],
        },
    )

    assert response.status_code == 409
    assert response.json()["detail"] == (
        "Account is already active. Please log in."
    )
    assert "access_token" not in response.json()

    # The rejected request must leave the account unchanged.
    session.refresh(user)
    assert user.is_active is True
    assert user.auth_version == original_version


def test_password_change_invalidates_old_tokens(client, session, registered_user, auth_headers):
    # Save the old token and version before changing the password.
    # Check the new hash, rejected old password/token, and usable new login.
    # Each assertion covers a different part of credential rotation.
    email = registered_user.user.email
    old_password = registered_user.password
    new_password = "NewPassword456!"
    old_headers = auth_headers

    user = registered_user.user
    original_version = user.auth_version

    # Change the password using the current token and password.
    change_response = client.patch(
        "/users/me/password",
        headers=old_headers,
        json={
            "current_password": old_password,
            "new_password": new_password,
        },
    )

    assert change_response.status_code == 204
    assert change_response.content == b"" # no bytes, that's what b is

    # Verify the new hash and incremented version were persisted.
    session.refresh(user)
    assert verify_password(new_password, user.hashed_password)
    assert not verify_password(old_password, user.hashed_password)
    assert user.auth_version == original_version + 1

    # The token issued before the password change must be rejected.
    old_token_response = client.get("/users/me", headers=old_headers)
    assert old_token_response.status_code == 401

    # The old password must no longer allow login.
    old_login_response = client.post(
        "/users/token",
        data={"username": email, "password": old_password},
    )
    assert old_login_response.status_code == 401
    assert "access_token" not in old_login_response.json()

    # The new password must issue a working token.
    new_login_response = client.post(
        "/users/token",
        data={"username": email, "password": new_password},
    )
    assert new_login_response.status_code == 200

    new_headers = {
        "Authorization": (
            f"Bearer {new_login_response.json()['access_token']}"
        ),
    }
    profile_response = client.get("/users/me", headers=new_headers)

    assert profile_response.status_code == 200
    assert profile_response.json()["id"] == registered_user.public["id"]
