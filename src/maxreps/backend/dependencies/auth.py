# Implement these in order after the User migration and registration/login
# routes exist.
from typing import Annotated

from fastapi.security import OAuth2PasswordBearer
from fastapi import HTTPException, Depends, status

from ..models.user import User
from ..dependencies.db import SessionDep
from ...services.security import decode_access_token, InvalidAccessTokenError


oauth2_scheme = OAuth2PasswordBearer(tokenUrl="/users/token")


CREDENTIALS_EXCEPTION = HTTPException(
    status_code=status.HTTP_401_UNAUTHORIZED, 
    headers={"WWW-Authenticate" : "Bearer"},
    detail="Could not validate credentials"
)


def get_current_user(
        session : SessionDep,
        token: Annotated[str, Depends(oauth2_scheme)],
        ) -> User:
    try:
        user_id = decode_access_token(token=token)
    except InvalidAccessTokenError as e:
        raise CREDENTIALS_EXCEPTION from e

    user = session.get(User, user_id)

    if user is None:
        raise CREDENTIALS_EXCEPTION

    return user
    

def get_current_active_user(
        current_user : Annotated[User, Depends(get_current_user)],
) -> User:
    if not current_user.is_active:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail='Inactive User'
        )
    return current_user


def require_admin(active_user : Annotated[User, Depends(get_current_active_user)]) -> User:
    if not active_user.is_admin:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail='Not authorized for admin routes'
        )
    return active_user


CurrentUser = Annotated[User, Depends(get_current_active_user)]
AdminUser = Annotated[User, Depends(require_admin)]