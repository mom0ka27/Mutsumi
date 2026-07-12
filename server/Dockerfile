FROM python:3.13-slim

COPY --from=ghcr.io/astral-sh/uv:0.9.30 /uv /uvx /bin/

WORKDIR /app

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    UV_COMPILE_BYTECODE=1 \
    UV_LINK_MODE=copy

COPY pyproject.toml uv.lock ./
RUN uv sync --locked --no-dev --no-install-project

COPY app ./app
COPY run.py ./

EXPOSE 12091

CMD ["uv", "run", "--no-sync", "python", "run.py"]
