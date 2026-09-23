'''
This file sets up the Exercise table model along with a model to create and validate 
Exercise objects
'''
from sqlmodel import SQLModel, Field


class ExerciseCreate(SQLModel):
    name: str
    category: str
    instructions: list[str]


class Exercise(SQLModel, table=True):
    id: int | None = Field(default=None, primary_key=True)
    name: str = Field(index=True)
    category: str
    instructions: str