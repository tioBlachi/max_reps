"""Create the sole administrator before the application accepts requests."""

from pydantic import ValidationError
from sqlalchemy.exc import IntegrityError, SQLAlchemyError
from sqlmodel import Session, select

from maxreps.backend.models.user import User, UserCreate
from maxreps.services.security import get_password_hash, require_env


def ensure_admin_user(session: Session) -> None:
    # This runs on every startup, but creates an account only once. In particular,
    # restarting must not reset a password/email changed through the user routes.
    existing_admin = session.exec(
        select(User).where(User.is_admin.is_(True))
    ).first()
    if existing_admin is not None:
        return

    # Credentials are supplied by the deployment, never by public registration.
    # Reuse the registration rules, but suppress validation errors that could
    # otherwise include the plaintext password in a startup traceback.
    email = require_env("ADMIN_EMAIL")
    password = require_env("ADMIN_PASSWORD")
    try:
        credentials = UserCreate(email=email.strip(), password=password)
    except ValidationError:
        raise RuntimeError(
            "ADMIN_EMAIL must be a valid email address and ADMIN_PASSWORD "
            "must contain between 8 and 128 characters"
        ) from None

    normalized_email = str(credentials.email).lower()
    email_owner = session.exec(
        select(User).where(User.email == normalized_email)
    ).first()
    if email_owner is not None:
        # Email alone does not prove ownership of an existing ordinary account.
        # Resolve this deliberately in the database instead of silently promoting it.
        raise RuntimeError(
            "ADMIN_EMAIL already belongs to a non-admin user; "
            "resolve that account before bootstrapping the administrator"
        )

    admin = User(
        email=normalized_email,
        hashed_password=get_password_hash(credentials.password),
        is_admin=True,
        is_active=True,
    )
    session.add(admin)
    try:
        session.commit()
    except IntegrityError:
        session.rollback()
        # Two server workers can both see an empty admin slot. The unique partial
        # index lets only one insert succeed. Accept the winner after rollback.
        if session.exec(select(User).where(User.is_admin.is_(True))).first() is not None:
            return
        raise RuntimeError(
            "Could not create the administrator because of a database constraint"
        ) from None
    except SQLAlchemyError:
        session.rollback()
        raise
