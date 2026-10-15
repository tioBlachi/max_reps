from uuid import UUID, uuid4
from datetime import datetime, timezone
from typing import TYPE_CHECKING

from sqlmodel import SQLModel, Field, Relationship
from sqlalchemy import Index, text
from pydantic import EmailStr

if TYPE_CHECKING:
    from .lift_record import LiftRecord

class UserBase(SQLModel):
    email : EmailStr = Field(index=True, unique=True)


class UserCreate(UserBase):
    password : str = Field(min_length=8, max_length=128)


class UserPublic(UserBase):
    id : UUID
    is_admin: bool = False


class UserEmailUpdate(SQLModel):
    current_password : str
    email : EmailStr


class UserPasswordUpdate(SQLModel):
    current_password: str = Field(min_length=1, max_length=128)
    new_password: str = Field(min_length=8, max_length=128)


class UserDeactivate(SQLModel):
    current_password : str


class User(UserBase, table=True):
    __tablename__ = 'users'
    __table_args__ = (
        Index(
            "uq_users_single_admin",
            "is_admin",
            unique=True,
            postgresql_where=text("is_admin IS TRUE"),
            sqlite_where=text("is_admin = 1"),
        ),
    )
    id : UUID = Field(default_factory=uuid4, primary_key=True)
    hashed_password : str
    is_active : bool = Field(default=True)
    is_admin : bool = Field(default=False)
    auth_version : int = Field(default=1, nullable=False)
    registered_at : datetime | None = Field(
        default_factory=lambda: datetime.now(timezone.utc),
        nullable=True
    )
    deactivated_at : datetime | None = Field(
            default=None,
            nullable=True
        )
    reactivated_at : datetime | None = Field(
            default= None,
            nullable=True
        )
    lift_records: list["LiftRecord"] = Relationship(
        back_populates="user",
        passive_deletes="all",
    )
