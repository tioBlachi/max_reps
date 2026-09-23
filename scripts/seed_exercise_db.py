import json
from pathlib import Path

from sqlmodel import Session

from maxreps.backend.dependencies.db import engine
from maxreps.backend.models.exercise import ExerciseCreate, Exercise

json_path = Path(__file__).resolve().parents[1] / "seed_data" / "response.json"


def seed_exercises(session: Session) -> None:
    with json_path.open(mode='r', encoding='utf-8') as file:
        exercise_data = json.load(file)

        for item in exercise_data:
            name = item['name']
            category = item['category'] if item['type'] == 'reps' else None
            instructions = item['instructions']

            exercise_create = ExerciseCreate(
                name=name,
                category=category,
                instructions=instructions
            )

            new_exercise = Exercise.model_validate(exercise_create)

            session.add(new_exercise)

        session.commit()


def main() -> None:
    with Session(engine) as session:
        seed_exercises(session)


if __name__ == "__main__":
    main()
