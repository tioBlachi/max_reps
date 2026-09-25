import os
from datetime import datetime, timedelta, timezone
from uuid import UUID

import jwt
from jwt.exceptions import InvalidTokenError

from pwdlib import PasswordHash

class InvalidAccessTokenError(Exception):
    '''This is raised when an access token cannot be validated.'''


def require_env(name: str) -> str:
    value = os.getenv(name)

    if value is None or not value.strip():
        raise RuntimeError(f"{name} must be configured")
    return value

SECRET_KEY=require_env("SECRET_KEY")
ALGORITHM = require_env("ALGORITHM")
try:
    ACCESS_TOKEN_EXPIRATION_MINUTES = int(
        require_env("ACCESS_TOKEN_EXPIRATION_MINUTES")
        )
    if ACCESS_TOKEN_EXPIRATION_MINUTES <= 0:
        raise RuntimeError(
            'ACCESS_TOKEN_EXPIRATION_MINUTES must be greater than zero'
        )
except ValueError:
    raise RuntimeError(
        "ACCESS_TOKEN_EXPIRATION_MINUTES must be an integer"
        ) from None


# Password Verification
password_hash = PasswordHash.recommended()

def verify_password(plain_password : str, hashed_password : str) -> bool:
    return password_hash.verify(plain_password, hashed_password)


def get_password_hash(password : str) -> str:
    return password_hash.hash(password)


# Create JWT Token
def create_access_token(user_id: UUID, expires_delta : timedelta | None = None) -> str:
    issued_at = datetime.now(timezone.utc)

    if expires_delta is not None:
        expires_at = issued_at + expires_delta
    else:
        # Fallback to the environment variable for token expiration
        expires_at = issued_at + timedelta(
            minutes=ACCESS_TOKEN_EXPIRATION_MINUTES
        )

    payload = {
        'sub': str(user_id),
        'iat': issued_at,
        'exp': expires_at,
    }

    return jwt.encode(
        payload,
        SECRET_KEY,
        ALGORITHM
    )


def decode_access_token(token: str) -> UUID:
    try:
        payload = jwt.decode(
            token,
            SECRET_KEY,
            algorithms=[ALGORITHM],
            options={
                'require' : ['sub', 'iat', 'exp']
            },
        )
        return UUID(payload['sub'])
    except (InvalidTokenError, ValueError) as e:
        raise InvalidAccessTokenError from e