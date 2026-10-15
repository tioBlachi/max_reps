from contextlib import asynccontextmanager

from fastapi import FastAPI, status
from fastapi.middleware.cors import CORSMiddleware
from guard import SecurityMiddleware
from sqlmodel import Session

from maxreps.backend.dependencies.db import engine
from maxreps.services.bootstrap import ensure_admin_user
from maxreps.services.security import config, guard_deco
from maxreps.backend.routes.exercise import router as exercise_router
from maxreps.backend.routes.user import router as user_router
from maxreps.backend.routes.lift_record import router as lift_record_router
from maxreps.backend.routes.admin import router as admin_router


@asynccontextmanager
async def lifespan(app: FastAPI):
    # Code before yield runs during startup. Alembic must have created the tables
    # first (Docker Compose already applies migrations before launching Uvicorn).
    with Session(engine) as session:
        ensure_admin_user(session)
    # The account is committed and the startup session closed before requests run.
    yield


app = FastAPI(
    description='The backend for the MaxReps applicaiton',
    lifespan=lifespan,
)

app.include_router(exercise_router)
app.include_router(user_router)
app.include_router(lift_record_router)
app.include_router(admin_router)


app.add_middleware(SecurityMiddleware, config=config)
app.add_middleware(
    CORSMiddleware,
    allow_origins=['http://localhost:3000'],
    allow_methods=['GET', 'POST'],
    allow_headers=['Content-Type', 'Authorization'],
    allow_credentials=False,
)

app.state.guard_decorator = guard_deco


@app.get('/health', status_code=status.HTTP_200_OK)
def check_health():
    return {'status' : 'healthy'}
