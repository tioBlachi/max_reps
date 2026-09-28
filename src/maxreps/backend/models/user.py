from uuid import UUID, uuid4
from typing import TYPE_CHECKING

from sqlmodel import SQLModel, Field, Relationship
from pydantic import EmailStr

if TYPE_CHECKING:
    from .lift_record import LiftRecord

class UserBase(SQLModel):
    email : EmailStr = Field(index=True, unique=True)


class UserCreate(UserBase):
    password : str = Field(min_length=8, max_length=128)


class UserPublic(UserBase):
    id : UUID


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
    id : UUID = Field(default_factory=uuid4, primary_key=True)
    hashed_password : str
    is_active : bool = Field(default=True)
    is_admin : bool = Field(default=False)
    auth_version : int = Field(default=1, nullable=False)
    lift_records: list["LiftRecord"] = Relationship(
        back_populates="user",
    )
