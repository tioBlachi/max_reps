from typing import Annotated
from uuid import UUID
from datetime import datetime, timedelta, timezone

from fastapi import (
    APIRouter,
    HTTPException,
    Query,
    status,
)
from sqlalchemy import delete, func
from sqlalchemy.exc import SQLAlchemyError
from sqlmodel import select

from maxreps.backend.dependencies.auth import AdminUser
from maxreps.backend.dependencies.db import SessionDep
from maxreps.backend.models.admin import (
    AdminStats,
    AdminUserList,
    AdminUserPublic,
    InactiveCleanupPreview,
    InactiveCleanupRequest,
    InactiveCleanupResult,
)
from maxreps.backend.models.user import User
from maxreps.services.security import (
    guard_deco,
    rate_window,
)


router = APIRouter(
    prefix='/admin',
    tags=['Admin']
)


def _inactive_cleanup_cutoff() -> datetime:
    return datetime.now(timezone.utc) - timedelta(days=90)


def _inactive_cleanup_conditions(cutoff: datetime):
    # SQL comparisons exclude NULL dates. Check current status as well as age:
    # reactivated accounts must survive even if they retain an old timestamp.
    return (
        User.is_active.is_(False),
        User.is_admin.is_(False),
        User.deactivated_at <= cutoff,
    )


@router.get(
    '/inactive-users/cleanup',
    response_model=InactiveCleanupPreview,
    description=(
        'Previews the number of regular accounts inactive for at least 90 days. '
        'Uses the latest deactivated_at timestamp in UTC; accounts with no date '
        'are excluded. Requires an authenticated active admin. '
        'Rate limited to 30 requests per minute.'
    ),
)
@guard_deco.rate_limit(requests=30, window=60)
def preview_inactive_cleanup(
    session: SessionDep,
    current_admin: AdminUser,
) -> InactiveCleanupPreview:
    cutoff = _inactive_cleanup_cutoff()
    count = session.exec(
        select(func.count(User.id)).where(*_inactive_cleanup_conditions(cutoff))
    ).one()
    return InactiveCleanupPreview(eligible_users=count, cutoff_at=cutoff)


@router.delete(
    '/inactive-users/cleanup',
    response_model=InactiveCleanupResult,
    description=(
        'Permanently deletes eligible inactive regular accounts and their lift '
        'records. Send the UTC cutoff_at returned by the preview; it must be '
        'at least 90 days ago. Eligibility is rechecked during deletion. '
        'Admin accounts, active accounts, and accounts with no deactivation date '
        'are preserved. Requires an authenticated active admin. '
        'Rate limited to 5 requests per 10 minutes in production and '
        '5 requests per minute during development.'
    ),
)
@guard_deco.rate_limit(requests=5, window=rate_window(600))
def cleanup_inactive_users(
    cleanup: InactiveCleanupRequest,
    session: SessionDep,
    current_admin: AdminUser,
) -> InactiveCleanupResult:
    cutoff = cleanup.cutoff_at
    if cutoff.utcoffset() is None:
        cutoff = cutoff.replace(tzinfo=timezone.utc)
    else:
        cutoff = cutoff.astimezone(timezone.utc)
    if cutoff > _inactive_cleanup_cutoff():
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_CONTENT,
            detail='The cleanup cutoff must be at least 90 days ago',
        )

    try:
        # A single conditional DELETE rechecks status in the database, rather
        # than deleting IDs from a potentially stale preview. The existing FK
        # cascade removes only these accounts' lift records in this transaction.
        result = session.execute(
            delete(User)
            .where(*_inactive_cleanup_conditions(cutoff))
            .execution_options(synchronize_session=False)
        )
        deleted_users = result.rowcount
        session.commit()
    except SQLAlchemyError:
        session.rollback()
        raise

    return InactiveCleanupResult(deleted_users=deleted_users)

#------------USER STATS-------------
@router.get(
    '/stats',
    response_model=AdminStats,
    description=(
        "Returns total, active, and inactive account counts. "
        "Includes the admin account and excludes permanently deleted accounts. "
        "Requires an authenticated active admin.\n\n"
        "Rate limited to:\n\n"
        "- 30 requests per minute in production\n"
        "- 30 requests per minute during development"
    ),
)
@guard_deco.rate_limit(requests=30, window=60)
def get_user_stats(
    session: SessionDep,
    current_admin: AdminUser,
) -> AdminStats:
    statement = (
        select(User.is_active, func.count(User.id))
        .group_by(User.is_active)
    )

    counts = dict(session.exec(statement).all())
    active = counts.get(True, 0)
    inactive = counts.get(False, 0)

    return AdminStats(
        total_users=active + inactive,
        active_users=active,
        inactive_users=inactive,
        )


#-----------USER LIST----------------
@router.get(
    "/users",
    response_model=AdminUserList,
    description=(
        "Returns account information and lifecycle timestamps for admin review. "
        "Supports an optional active-status filter and pagination. "
        "Total counts all matching accounts, not just the current page. "
        "Requires an authenticated active admin.\n\n"
        "Rate limited to:\n\n"
        "- 30 requests per minute in production\n"
        "- 30 requests per minute during development"
    ),
)
@guard_deco.rate_limit(requests=30, window=60)
def get_users(
    session: SessionDep,
    current_admin: AdminUser,
    is_active: bool | None = None,
    offset: Annotated[int, Query(ge=0)] = 0,
    limit: Annotated[int, Query(ge=1, le=100)] = 20,
) -> AdminUserList:
    statement = select(User)
    count_statement = select(func.count(User.id))

    if is_active is not None:
        statement = statement.where(User.is_active == is_active)
        count_statement = count_statement.where(User.is_active == is_active)

    total = session.exec(count_statement).one()

    users = session.exec(
        statement.order_by(User.email).offset(offset).limit(limit)
    ).all()

    return AdminUserList(
        total=total,
        offset=offset,
        limit=limit,
        users=[
            AdminUserPublic.model_validate(user, from_attributes=True) for user in users
        ]
    )


# ---------- PERMANENT USER DELETION ----------
@router.delete(
    "/users/{user_id}",
    status_code=status.HTTP_204_NO_CONTENT,
    description=(
        "Permanently deletes a regular account and its lift records. "
        "Preserves the exercise catalog. Admin accounts cannot be deleted. "
        "Requires an authenticated active admin.\n\n"
        "Rate limited to:\n\n"
        "- 5 requests per 10 minutes in production\n"
        "- 5 requests per minute during development"
    ),
)
@guard_deco.rate_limit(requests=5, window=rate_window(600))
def delete_user(
    user_id: UUID,
    session: SessionDep,
    current_admin: AdminUser,
) -> None:
    user = session.get(User, user_id)

    if user is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail='User not found'
        )

    if user.id == current_admin.id or user.is_admin:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail='Admin accounts cannot be deleted'
        )

    try:
        session.delete(user)
        session.commit()
    except SQLAlchemyError:
        session.rollback()
        raise
