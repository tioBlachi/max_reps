import json
from pathlib import Path

from sqlmodel import Session, select

from maxreps.backend.dependencies.db import engine
from maxreps.backend.models.exercise import ExerciseCreate, Exercise

json_path = Path(__file__).resolve().parents[1] / "seed_data" / "response.json"


def seed_exercises(session: Session) -> None:
    # Check to see if Exercise table is already seeded at first startup
    existing_exercise = session.exec(select(Exercise)).first()
    
    if existing_exercise is not None:
        print("Exercise table already exists")
        return

    # Exercise table is empty, seed it with the response.json file
    with json_path.open(mode='r', encoding='utf-8') as file:
        exercise_data = json.load(file)

        for item in exercise_data:
            if item['type'] != 'reps':
                continue

            exercise_create = ExerciseCreate(
                name=item['name'],
                category=item['category'],
                instructions=item['instructions']
            )

            new_exercise = Exercise.model_validate(exercise_create)
            session.add(new_exercise)

        session.commit()


def main() -> None:
    with Session(engine) as session:
        seed_exercises(session)


if __name__ == "__main__":
    main()
