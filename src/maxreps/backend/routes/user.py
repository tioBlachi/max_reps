"""User registration, authentication, and self-service account routes."""

from typing import Annotated

from fastapi import (
    APIRouter,
    status,
    HTTPException,
    Depends
    )
from fastapi.security import OAuth2PasswordRequestForm
from sqlalchemy.exc import IntegrityError, SQLAlchemyError
from sqlmodel import select

from maxreps.backend.dependencies.db import SessionDep
from maxreps.backend.dependencies.auth import CREDENTIALS_EXCEPTION
from maxreps.backend.models.token import Token
from maxreps.backend.models.user import (
    User,
    UserPublic,
    UserCreate,
    UserEmailUpdate,
    UserPasswordUpdate,
    UserDeactivate,
    )
from maxreps.services.security import (
    create_access_token,
    verify_password,
    get_password_hash,
    )
from maxreps.backend.dependencies.auth import CurrentUser
from maxreps.services.security import (
    guard_deco,
    rate_window,
)


router = APIRouter(
    prefix="/users",
    tags=["Users"],
)


# ----------- REGISTER NEW USER ---------------
@router.post(
    "",
    response_model=UserPublic,
    status_code=status.HTTP_201_CREATED,
    description=(
        "Register a user and store a hash of their password.\n\n"
        "Rate limited to:\n\n"
        "- 3 requests per hour in production\n"
        "- 3 requests per minute during development"
    ),
    
)
@guard_deco.require_ip(whitelist=['127.0.0.1', '172.18.0.1'])
@guard_deco.rate_limit(requests=3, window=rate_window(3600))
def register_user(session: SessionDep, user_data: UserCreate) -> User:
    normalized_email = str(user_data.email).strip().lower()
    user_in_db = session.exec(
        select(User).where(User.email == normalized_email)
    ).first()

    if user_in_db is not None:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="User already exists with that email address",
        )

    new_user = User(
        email=normalized_email,
        hashed_password=get_password_hash(user_data.password),
    )

    session.add(new_user)

    try:
        session.commit()
    except IntegrityError as exc:
        session.rollback()
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="User already exists with that email address",
        ) from exc

    session.refresh(new_user)
    return new_user


# ----------- LOGIN USER ---------------
@router.post(
    "/token",
    response_model=Token,
    status_code=status.HTTP_200_OK,
    description=(
        "Logs the user into the application and grants a JWT. "
        "Token expiration is configured by ACCESS_TOKEN_EXPIRATION_MINUTES.\n\n"
        "Rate limited to:\n\n"
        "- 10 requests per 5 minutes in production\n"
        "- 10 requests per minute during development"
    ),
)
@guard_deco.rate_limit(requests=10, window=rate_window(300))
def login_user(
    session: SessionDep,
    form_data: Annotated[OAuth2PasswordRequestForm, Depends()],
) -> Token:
    normalized_email = form_data.username.strip().lower()
    user = session.exec(
        select(User).where(User.email == normalized_email)
    ).first()

    if user is None or not verify_password(
        form_data.password,
        user.hashed_password,
    ):
        raise CREDENTIALS_EXCEPTION

    if not user.is_active:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Inactive user",
        )

    access_token = create_access_token(user.id)
    return Token(access_token=access_token)


# ----------- GET CURRENT USER ---------------
@router.get(
    "/me",
    response_model=UserPublic,
    description=(
        "Returns the current user. Information can be used to populate a user profile page.\n\n"
        "Rate limited to:\n\n"
        "- 60 requests per minute in production\n"
        "- 60 requests per minute during development"
    ),
)
@guard_deco.rate_limit(requests=60, window=60)
def get_my_profile(current_user: CurrentUser) -> User:
    return current_user


# ----------- UPDATE USER EMAIL ---------------
@router.patch(
    "/me/email",
    response_model=UserPublic,
    description=(
        "Updates the current user's email address after validating their current password "
        "and verifying that the new email is not already registered.\n\n"
        "Rate limited to:\n\n"
        "- 5 requests per 10 minutes in production\n"
        "- 5 requests per minute during development"
    ),
)
@guard_deco.rate_limit(requests=5, window=rate_window(600))
def update_user_email(
    session: SessionDep,
    update_data: UserEmailUpdate,
    current_user: CurrentUser,
) -> User:
    if not verify_password(
        update_data.current_password,
        current_user.hashed_password,
    ):
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Current password is incorrect",
        )

    new_email = str(update_data.email).strip().lower()
    email_owner = session.exec(
        select(User).where(User.email == new_email)
    ).first()

    if email_owner is not None and email_owner.id != current_user.id:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="Another user is already registered with this email",
        )

    current_user.email = new_email
    session.add(current_user)

    try:
        session.commit()
    except IntegrityError as exc:
        session.rollback()
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="Another user is already registered with this email",
        ) from exc

    session.refresh(current_user)
    return current_user


# ----------- UPDATE USER PASSWORD ---------------
@router.patch(
    "/me/password",
    status_code=status.HTTP_204_NO_CONTENT,
    description=(
        "Updates the current user's password after validating their current password.\n\n"
        "Rate limited to:\n\n"
        "- 5 requests per 10 minutes in production\n"
        "- 5 requests per minute during development"
    ),
)
@guard_deco.rate_limit(requests=5, window=rate_window(600))
def update_user_password(
    session: SessionDep,
    update_data: UserPasswordUpdate,
    current_user: CurrentUser,
) -> None:
    if not verify_password(
        update_data.current_password,
        current_user.hashed_password,
    ):
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Current password is incorrect",
        )

    current_user.hashed_password = get_password_hash(update_data.new_password)
    session.add(current_user)
    session.commit()


# ----------- DELETE/DEACTIVATE USER ---------------
@router.delete(
    "/me/deactivate",
    status_code=status.HTTP_204_NO_CONTENT,
    description=(
        "Deactivates the current user's account after validating their current password. "
        "Sets is_active to False without deleting the user.\n\n"
        "Rate limited to:\n\n"
        "- 5 requests per 10 minutes in production\n"
        "- 5 requests per minute during development"
    ),
)
@guard_deco.rate_limit(requests=5, window=rate_window(600))
def deactivate_user(
    session: SessionDep,
    confirm_data: UserDeactivate,
    current_user: CurrentUser,
) -> None:
    if not verify_password(
        confirm_data.current_password,
        current_user.hashed_password,
    ):
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Current password is incorrect",
        )
        
    current_user.is_active = False

    session.add(current_user)
    session.commit()


# ----------- REACTIVATE USER ----------------
@router.post(
        '/reactivate',
        response_model=Token,
        description=(
            "Reactivates an inactive account after verifying the user's email and password. "
            "Sets is_active to True and returns a JWT.\n\n"
            "Rate limited to:\n\n"
            "- 10 requests per 5 minutes in production\n"
            "- 10 requests per minute during development"
        ),
        )
@guard_deco.rate_limit(requests=10, window=rate_window(300))
def reactivate_user(
    session: SessionDep,
    form_data: Annotated[OAuth2PasswordRequestForm, Depends()]) -> Token:
    normalized_email = form_data.username.strip().lower()

    user = session.exec(
            select(User).where(User.email == normalized_email)
        ).first()

    if user is None or not verify_password(
        form_data.password,
        user.hashed_password,):
        raise CREDENTIALS_EXCEPTION

    if user.is_active:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail='Account is already active. Please log in.',
        )

    user.is_active = True
    session.add(user)

    try:
        session.commit()
    except SQLAlchemyError:
        session.rollback()
        raise

    return Token(access_token=create_access_token(user.id))
