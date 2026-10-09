from fastapi import FastAPI, status
from guard import SecurityMiddleware
from maxreps.services.security import config, guard_deco
from maxreps.backend.routes.exercise import router as exercise_router
from maxreps.backend.routes.user import router as user_router
from maxreps.backend.routes.lift_record import router as lift_record_router
from maxreps.backend.routes.admin import router as admin_router


app = FastAPI(
    description='The backend for the MaxReps applicaiton',
)

app.include_router(exercise_router)
app.include_router(user_router)
app.include_router(lift_record_router)
app.include_router(admin_router)


app.add_middleware(SecurityMiddleware, config=config)

app.state.guard_decorator = guard_deco


@app.get('/health', status_code=status.HTTP_200_OK)
def check_health():
    return {'status' : 'healthy'}
