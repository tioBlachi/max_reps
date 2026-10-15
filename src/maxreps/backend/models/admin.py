from datetime import datetime

from sqlmodel import SQLModel

from maxreps.backend.models.user import UserPublic


class AdminUserPublic(UserPublic):
    is_active: bool
    is_admin: bool
    registered_at: datetime | None
    deactivated_at: datetime | None
    reactivated_at: datetime | None


class AdminUserList(SQLModel):
    total: int
    offset: int
    limit: int
    users: list[AdminUserPublic]


class AdminStats(SQLModel):
    total_users: int
    active_users: int
    inactive_users: int


class InactiveCleanupPreview(SQLModel):
    eligible_users: int
    cutoff_at: datetime


class InactiveCleanupRequest(SQLModel):
    cutoff_at: datetime


class InactiveCleanupResult(SQLModel):
    deleted_users: int
