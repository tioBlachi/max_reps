import os

from fastapi import FastAPI, status
from guard import SecurityMiddleware, SecurityConfig, SecurityDecorator

app = FastAPI(
    description='The backend for the MaxReps applicaiton',
)

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
