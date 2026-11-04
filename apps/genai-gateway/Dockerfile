# add actual value
ARG PYTHON_IMAGE=python:3.12-slim

FROM ${PYTHON_IMAGE} AS build
COPY --from=ghcr.io/astral-sh/uv:0.9 /uv /bin/uv
ENV UV_COMPILE_BYTECODE=1 UV_LINK_MODE=copy UV_PYTHON_DOWNLOADS=never
WORKDIR /app
COPY pyproject.toml uv.lock ./
RUN uv sync --frozen --no-dev
COPY app ./app

FROM ${PYTHON_IMAGE}
RUN groupadd --gid 1000 app && useradd --uid 1000 --gid 1000 --no-create-home app
WORKDIR /app
COPY --from=build --chown=1000:1000 /app /app
ENV PATH=/app/.venv/bin:$PATH PYTHONUNBUFFERED=1 PYTHONDONTWRITEBYTECODE=1
USER 1000:1000
EXPOSE 8080
CMD ["uvicorn", "--factory", "app.main:build", "--host", "0.0.0.0", "--port", "8080", "--no-access-log"]
