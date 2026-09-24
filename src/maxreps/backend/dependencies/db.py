import os
from typing import Annotated

from fastapi import Depends
from sqlmodel import create_engine, Session

DATABASE_URL = os.environ["DATABASE_URL"]

engine = create_engine(
    url=DATABASE_URL,
    echo=True
    )

def get_session():
    with Session(engine) as session:
        yield session

SessionDep = Annotated[Session, Depends(get_session)]
