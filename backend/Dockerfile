# syntax=docker/dockerfile:1
#
# Build context is THIS directory (`docker build backend/`): the image never reaches
# outside backend/, so it builds identically in the monorepo, in CI and on its own.

# ----------------------------- builder -----------------------------
# Builds the virtualenv at /opt/venv from the locked dependencies.
FROM python:3.13-slim AS builder

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    UV_COMPILE_BYTECODE=1 \
    UV_LINK_MODE=copy \
    UV_PYTHON_DOWNLOADS=0 \
    UV_PROJECT_ENVIRONMENT=/opt/venv

# build-essential/gcc/libpq-dev for any source builds; git for the django-stdimage
# git dependency; gettext (msgfmt) because django-stdimage compiles .po -> .mo in its
# build backend and the source build fails without it.
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential python3-dev libpq-dev gcc git gettext \
    && rm -rf /var/lib/apt/lists/*

RUN pip install --no-cache-dir uv

# Set to "true" to include the dev dependency group (used by the test image).
ARG INSTALL_DEV=false

WORKDIR /app
COPY pyproject.toml uv.lock ./
RUN if [ "$INSTALL_DEV" = "true" ]; then uv sync --frozen; else uv sync --frozen --no-dev; fi

# ----------------------------- runtime -----------------------------
FROM python:3.13-slim AS runtime

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PATH="/opt/venv/bin:$PATH"

# gettext -> msgfmt (translations are compiled below); curl -> container healthcheck.
RUN apt-get update && apt-get install -y --no-install-recommends \
    gettext curl \
    && rm -rf /var/lib/apt/lists/* \
    && useradd --create-home --uid 1000 app

# Build identity, not environment config: CI passes the git sha / tag so the running
# app can report it (/api/v1/meta/). Anything environment-specific stays in env vars.
ARG APP_VERSION=dev
ENV APP_VERSION=$APP_VERSION

WORKDIR /app
COPY --from=builder /opt/venv /opt/venv
COPY . .
# Compile translations at build time (msgfmt only, no Django settings needed), so the
# runtime never writes into the image and the release step stays schema-only.
RUN find . -name 'django.po' -execdir msgfmt --check -o django.mo django.po \; \
    && chown -R app:app /app
USER app

EXPOSE 8000

# Web process. Workers: `celery -A config worker ...`, beat: `celery -A config beat ...`,
# release step: `bash scripts/release.sh` (see ops/compose/docker-compose.yml).
CMD ["bash", "scripts/entrypoint.sh"]
