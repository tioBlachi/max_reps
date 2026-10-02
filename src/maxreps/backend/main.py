import os

from fastapi import FastAPI, status
from guard import SecurityMiddleware, SecurityConfig
from maxreps.backend.routes.exercise import router as exercise_router
from maxreps.backend.routes.user import router as user_router
from maxreps.backend.routes.lift_record import router as lift_record_router

app = FastAPI(
    description='The backend for the MaxReps applicaiton',
)

app.include_router(exercise_router)
app.include_router(user_router)
app.include_router(lift_record_router)

config = SecurityConfig(
    enable_rate_limiting=True,
    rate_limit=3,
    enable_redis=True,
    redis_url=os.getenv("REDIS_URL", "redis://localhost:6379/0"),
    passive_mode=True,
)

app.add_middleware(SecurityMiddleware, config=config)


@app.get('/health', status_code=status.HTTP_200_OK)
def check_health():
    return {'status' : 'healthy'}
