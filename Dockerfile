FROM python:3.14-slim-trixie

RUN pip install uv

WORKDIR /app

COPY pyproject.toml uv.lock ./

RUN uv sync --frozen --no-install-project

COPY . .

RUN uv sync --frozen

CMD ["uv", "run", "uvicorn", "maxreps.backend.main:app", "--host", "0.0.0.0", "--port", "8000"]