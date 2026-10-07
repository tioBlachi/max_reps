from fastapi import APIRouter, HTTPException, status
from sqlmodel import select

from maxreps.backend.dependencies.db import SessionDep
from maxreps.backend.models.exercise import (
    Exercise,
    ExercisePublic,
    ExerciseSummary,
)
from maxreps.services.security import guard_deco


router = APIRouter(
    prefix='/exercises',
    tags=["Exercises"]
    )


@router.get('/',
    response_model=list[ExerciseSummary],
    status_code=status.HTTP_200_OK,
    description="Endpoint that returns name, category and id of all exercises in " \
    "the database. Used to populate a frontend list of strings for autocomplete feature."
    )
@guard_deco.rate_limit(requests=60, window=60)
def get_all_exercises(
    session: SessionDep,
) -> list[Exercise]:
    '''This route will be used by the autocomplete feature on the front end'''
    statement = select(Exercise)

    exercises = session.exec(statement).all()

    return exercises


@router.get('/{exercise_id}',
            response_model=ExercisePublic,
            status_code=status.HTTP_200_OK,
            description="Endpoint that additionally returns instructions as a list of strings" \
            "for a specific exercise id.")
@guard_deco.rate_limit(requests=120, window=60)
def get_exercise(
    exercise_id: int,
    session: SessionDep
) -> Exercise:
    '''This route will be used by the frontend when an exercise is selected
    from the autocomplete options. Used to provide exercise instructions'''
    exercise = session.get(Exercise, exercise_id)

    if exercise is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail='Exercise not found'
        )

    return exercise