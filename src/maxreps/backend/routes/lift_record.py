from typing import Annotated
from uuid import UUID
from datetime import timezone

from fastapi import (
    APIRouter,
    HTTPException,
    Query,
    status,
    )
from maxreps.backend.models.lift_record import (
    LiftRecord,
    LiftRecordCreate,
    LiftRecordPublic
    )
from maxreps.services.utils import (
    epley,
    to_kilograms,
    from_kilograms,
)
from sqlmodel import select
from sqlalchemy.exc import SQLAlchemyError
from maxreps.backend.models.exercise import Exercise
from maxreps.backend.dependencies.db import SessionDep
from maxreps.backend.dependencies.auth import CurrentUser
from maxreps.backend.models.enums import WeightUnit
from maxreps.services.security import guard_deco


router = APIRouter(
    prefix='/lift_record',
    tags=['Lift Records'],
)


# ---------- HELPERS ------------------------
def to_public(record: LiftRecord, unit: WeightUnit)-> LiftRecordPublic:
    return LiftRecordPublic(
        id=record.id,
        user_id=record.user_id,
        exercise_id=record.exercise_id,
        reps=record.reps,
        attempted_at=record.attempted_at,
        weight=from_kilograms(record.weight_kg, unit),
        unit=unit,
        one_rep_max_est=round(
            from_kilograms(record.one_rep_max_est, unit),
            2,
        ),
    ) 


# ---------- CREATE LIFT RECORD -------------
@router.post('/',
             response_model=LiftRecordPublic,
             status_code=status.HTTP_201_CREATED,
             description=(
                 "Creates a lift record for the authenticated active user and calculates "
                 "an estimated one-rep max using the Epley formula. Returns weight and "
                 "estimated max in the submitted unit, with the estimate rounded to two "
                 "decimal places. Timestamps without a timezone are interpreted as UTC; "
                 "timestamps with a timezone are converted to UTC. "
                 "Returns 404 if the exercise does not exist.\n\n"
                 "Rate limited to:\n\n"
                 "- 30 requests per minute in production\n"
                 "- 30 requests per minute during development"
             ))
@guard_deco.rate_limit(requests=30, window=60)
def create_lift_record(session: SessionDep, lift_data: LiftRecordCreate, current_user: CurrentUser) -> LiftRecordPublic:
    # confirm that the exercise exists
    exercise = session.get(Exercise, lift_data.exercise_id)

    if exercise is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=f'Exercise with id: {lift_data.exercise_id} not found'
        )

    # Set attempted_at and normalize to UTC
    attempted_at = lift_data.attempted_at

    if attempted_at.utcoffset() is None:
        attempted_at = attempted_at.replace(tzinfo=timezone.utc)
    else:
        attempted_at = attempted_at.astimezone(timezone.utc)

    # This will be the weight stored in the database in kgs
    weight_kg = to_kilograms(lift_data.weight, lift_data.unit)

    # Calculate the 1 rep max
    estimated_max_kg = epley(weight_kg, lift_data.reps)
    
    lift_record_to_store = LiftRecord(
        user_id=current_user.id,
        exercise_id=exercise.id,
        reps=lift_data.reps,
        attempted_at=attempted_at,
        weight_kg=weight_kg,
        one_rep_max_est=estimated_max_kg,
    )

    try:
        session.add(lift_record_to_store)
        session.commit()
    except SQLAlchemyError:
        session.rollback()
        raise

    session.refresh(lift_record_to_store)

    return to_public(lift_record_to_store, lift_data.unit)


# ---------- GET LIFT RECORD LIST -------------
@router.get(
    '/',
    response_model=list[LiftRecordPublic],
    status_code=status.HTTP_200_OK,
    description=(
        "Returns the authenticated active user's lift history, newest attempts first. "
        "Supports an optional exercise ID filter and pagination using offset and limit "
        "(default 20, maximum 100 records). Weight and estimated max are returned in "
        "the requested unit, defaulting to pounds, with estimates rounded to two decimal "
        "places. Returns an empty list if no records match.\n\n"
        "Rate limited to:\n\n"
        "- 60 requests per minute in production\n"
        "- 60 requests per minute during development"
    ),
    )
@guard_deco.rate_limit(requests=60, window=60)
def get_lift_records(
    session: SessionDep,
    current_user: CurrentUser,
    exercise_id: Annotated[int | None, Query(gt=0)] = None,
    unit: WeightUnit = WeightUnit.LB,
    offset: Annotated[int, Query(ge=0)] = 0,
    limit: Annotated[int, Query(ge=1, le=100)] = 20,
    ) -> list[LiftRecordPublic]:
    # Get authenticated user's lift records
    statement = select(LiftRecord).where(LiftRecord.user_id == current_user.id)
    # Possibly filter by one exercise
    if exercise_id is not None:
        statement = statement.where(LiftRecord.exercise_id == exercise_id)

    # Now sort everything by the latest attempts first
    statement = statement.order_by(
        LiftRecord.attempted_at.desc(),
        LiftRecord.id.desc(),
    ).offset(offset).limit(limit)

    records = session.exec(statement).all() # returns a list of lift records

    return [to_public(record, unit) for record in records]


# ---------- GET A SINGLE LIFT RECORD BY ID -------------
@router.get(
    '/{lift_record_id}',
    response_model=LiftRecordPublic,
    status_code=status.HTTP_200_OK,
    description=(
        "Returns a lift record by its UUID for the authenticated active user. "
        "Weight and estimated max are returned in the requested unit, defaulting to "
        "pounds, with the estimate rounded to two decimal places. Returns 404 if the "
        "record does not exist or belongs to another user.\n\n"
        "Rate limited to:\n\n"
        "- 60 requests per minute in production\n"
        "- 60 requests per minute during development"
    ),
)
@guard_deco.rate_limit(requests=60, window=60)
def get_lift_record(
    lift_record_id: UUID,
    session: SessionDep,
    current_user: CurrentUser,
    unit: WeightUnit = WeightUnit.LB,
) -> LiftRecordPublic:
    record = session.exec(
        select(LiftRecord).where(
            LiftRecord.id == lift_record_id,
            LiftRecord.user_id == current_user.id,
        )
    ).first()

    if record is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail='Lift record not found'
        )

    return to_public(record, unit)

