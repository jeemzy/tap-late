FROM node:22-bookworm-slim AS frontend
WORKDIR /ui
COPY frontend/package.json frontend/package-lock.json ./
RUN npm ci
COPY frontend/ ./
RUN npm run build

FROM ghcr.io/astral-sh/uv:0.9.9 AS uv
FROM python:3.12-slim-bookworm
COPY --from=uv /uv /uvx /bin/
WORKDIR /app
ENV PYTHONUNBUFFERED=1 UV_PROJECT_ENVIRONMENT=/opt/venv PATH="/opt/venv/bin:$PATH" \
    TAPLATE_DATA_DIR=/data TAPLATE_MODEL_DIR=/opt/taplate-models
COPY pyproject.toml uv.lock ./
RUN uv sync --locked --no-dev --no-install-project
COPY taplate/__init__.py taplate/config.py taplate/providers.py taplate/download_models.py ./taplate/
RUN python -m taplate.download_models \
    && useradd --create-home --uid 10001 taplate \
    && mkdir /data && chown taplate:taplate /data
COPY taplate/ ./taplate/
COPY --from=frontend /ui/dist ./frontend/dist
USER taplate
EXPOSE 8000
HEALTHCHECK --interval=30s --timeout=5s --start-period=20s CMD python -c "import urllib.request; urllib.request.urlopen('http://127.0.0.1:8000/api/health', timeout=4)" || exit 1
CMD ["uvicorn", "taplate.app:create_app", "--factory", "--host", "0.0.0.0", "--port", "8000", "--workers", "1"]
