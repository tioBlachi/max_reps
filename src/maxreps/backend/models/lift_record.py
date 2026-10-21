from datetime import datetime, timezone
from typing import TYPE_CHECKING
from uuid import UUID, uuid4

from sqlmodel import SQLModel, Relationship, Field

from .enums import WeightUnit

if TYPE_CHECKING:
    from .exercise import Exercise
    from .user import User


class LiftRecordBase(SQLModel):
    reps: int = Field(gt=0)
    attempted_at: datetime = Field(default_factory=lambda: datetime.now(timezone.utc))


class LiftRecordCreate(LiftRecordBase):
    exercise_id: int
    weight: float = Field(gt=0)
    unit: WeightUnit = WeightUnit.LB


class LiftRecordPublic(LiftRecordBase):
    id: UUID
    user_id: UUID
    exercise_id: int
    weight: float
    unit: WeightUnit
    one_rep_max_est: float
    is_recent: bool


class LiftRecord(LiftRecordBase, table=True):
    __tablename__ = 'lift_records'

    id : UUID = Field(default_factory=uuid4, primary_key=True)
    user_id : UUID = Field(
        foreign_key='users.id',
        ondelete='CASCADE',
        index=True,
    )
    exercise_id: int = Field(
        foreign_key='exercise.id',
        index=True,
    )

    weight_kg: float = Field(gt=0)
    one_rep_max_est : float = Field(gt=0)

    user: "User" = Relationship(
        back_populates='lift_records'
    )
    exercise: "Exercise" = Relationship(
        back_populates="lift_records"
    )
    