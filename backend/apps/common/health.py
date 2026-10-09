"""Liveness and readiness checks, shared by the middleware and the API views.

One implementation, two entry points:
  * ``common.middleware.HealthCheckMiddleware`` answers first (before Host validation
    and the HTTPS redirect), which is what Kubernetes probes and the Compose
    healthcheck rely on;
  * ``common.views.HealthzView`` / ``ReadyzView`` expose the same payloads as DRF views
    so they are part of the OpenAPI contract (api/openapi.yaml) and keep working even
    if the middleware is ever removed.
"""

import logging

from django.core.cache import cache
from django.db import connection

__all__ = ("HEALTH_STATES", "liveness", "readiness")

logger = logging.getLogger(__name__)

# Shared enum for every status field in the health payloads (one OpenAPI component,
# see ENUM_NAME_OVERRIDES in settings/third_party.py).
HEALTH_STATES = ("ok", "error")


def liveness() -> dict:
    """The process is up. Deliberately checks nothing else: if this depended on the
    database, a DB outage would make the orchestrator restart every web pod."""
    return {"status": "ok"}


def readiness() -> tuple[dict, int]:
    """The pod can serve traffic: database and cache answer. Returns (payload, status)."""
    checks = {"database": _check_database(), "cache": _check_cache()}
    healthy = all(result == "ok" for result in checks.values())
    return {"status": "ok" if healthy else "error", "checks": checks}, 200 if healthy else 503


def _check_database() -> str:
    try:
        with connection.cursor() as cursor:
            cursor.execute("SELECT 1")
    except Exception as exc:  # a probe must never 500, whatever the driver raises
        logger.warning("readiness: database check failed: %s", exc)
        return "error"
    return "ok"


def _check_cache() -> str:
    try:
        cache.set("readyz", "1", timeout=5)
        ok = cache.get("readyz") == "1"
    except Exception as exc:  # redis.exceptions.* are not DatabaseError
        logger.warning("readiness: cache check failed: %s", exc)
        return "error"
    return "ok" if ok else "error"
