from uuid import UUID, uuid4

from sqlmodel import SQLModel, Field
from pydantic import EmailStr

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
