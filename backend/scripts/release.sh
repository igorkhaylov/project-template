#!/bin/bash
# Release step: runs ONCE per deploy, before the new web/worker processes start.
#
#   Docker Compose: the `release` service (ops/compose/*.yml); `backend` waits for it
#                   with `condition: service_completed_successfully`.
#   Kubernetes:     a Job / Helm pre-upgrade hook with the same image and
#                   `command: ["bash", "scripts/release.sh"]`.
#
# Translations are compiled at image build time (Dockerfile), so nothing here writes
# into the image. Every step is idempotent, so re-running a failed release is safe.
set -euo pipefail

echo ">>> Applying database migrations..."
python manage.py migrate --no-input

echo ">>> Waiting for object storage (S3/MinIO)..."
# Static AND media are served from S3/MinIO with no local-filesystem fallback, so the
# bucket is a hard dependency. Fail fast with a clear message instead of a boto
# traceback from collectstatic. (Shared local MinIO: provision it once with `make minio`.)
python manage.py wait_for_storage

echo ">>> Collecting static files..."
# No --clear: never wipes the bucket.
python manage.py collectstatic --no-input

echo ">>> Ensuring superuser..."
python manage.py createsuperuserauto

echo ">>> Release complete."
