"""Database and API models for exercises."""
from typing import TYPE_CHECKING

from sqlalchemy import Column, JSON
from sqlmodel import Field, SQLModel, Relationship

if TYPE_CHECKING:
    from .lift_record import LiftRecord
class ExerciseBase(SQLModel):
    """Fields shared by all exercise representations."""

    name: str = Field(index=True)
    category: str


class ExerciseCreate(ExerciseBase):
    """Data required to create an exercise."""

    instructions: list[str]


class ExerciseSummary(ExerciseBase):
    """Lightweight exercise data for lists and autocomplete results."""

    id: int


class ExercisePublic(ExerciseSummary):
    """Complete exercise data returned by detail endpoints."""

    instructions: list[str]


class Exercise(ExerciseBase, table=True):
    """Exercise database table."""

    id: int | None = Field(default=None, primary_key=True)

    instructions: list[str] = Field(
        default_factory=list,
        sa_column=Column(JSON, nullable=False),
    )

    lift_records: list["LiftRecord"] = Relationship(
        back_populates='exercise'
    )
