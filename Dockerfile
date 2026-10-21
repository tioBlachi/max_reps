FROM ghcr.io/astral-sh/uv:python3.14-trixie-slim

# RUN pip install uv

WORKDIR /app

COPY pyproject.toml uv.lock ./

RUN uv sync --frozen --no-install-project

COPY . .

RUN uv sync --frozen

CMD ["sh", "-c", "uv run --frozen alembic upgrade head && uv run --frozen python scripts/seed_exercise_db.py && exec uv run --frozen uvicorn maxreps.backend.main:app --host 0.0.0.0 --port ${PORT:-8000}"]