#!/bin/bash
# Web process only (the image's default CMD).
#
# Schema migrations, collectstatic and the first superuser are NOT run here: they are a
# separate release step (scripts/release.sh) so that N replicas can start concurrently
# without racing on `migrate`. That is the Kubernetes model (a Job before the rollout),
# mirrored in Docker Compose by the `release` service that `backend` depends on.
set -euo pipefail

exec gunicorn config.wsgi:application \
    --name "${DJANGO_APP_NAME:-app}" \
    --workers "${GUNICORN_WORKERS:-2}" \
    --timeout "${GUNICORN_TIMEOUT:-60}" \
    --graceful-timeout "${GUNICORN_GRACEFUL_TIMEOUT:-30}" \
    --worker-tmp-dir /dev/shm \
    --bind 0.0.0.0:8000 \
    --access-logfile - \
    --error-logfile -
