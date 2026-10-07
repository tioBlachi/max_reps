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
    description=(
        "Returns the name, category, and ID of all exercises for exercise selection "
        "and frontend autocomplete.\n\n"
        "Rate limited to:\n\n"
        "- 60 requests per minute in production\n"
        "- 60 requests per minute during development"
    ),
    )
@guard_deco.rate_limit(requests=60, window=60)
def get_all_exercises(
    session: SessionDep,
) -> list[Exercise]:
    statement = select(Exercise)

    exercises = session.exec(statement).all()

    return exercises


@router.get('/{exercise_id}',
            response_model=ExercisePublic,
            status_code=status.HTTP_200_OK,
            description=(
                "Returns an exercise's name, category, ID, and instructions by exercise ID. "
                "Returns 404 if the exercise does not exist.\n\n"
                "Rate limited to:\n\n"
                "- 120 requests per minute in production\n"
                "- 120 requests per minute during development"
            ))
@guard_deco.rate_limit(requests=120, window=60)
def get_exercise(
    exercise_id: int,
    session: SessionDep
) -> Exercise:
    exercise = session.get(Exercise, exercise_id)

    if exercise is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail='Exercise not found'
        )

    return exercise
