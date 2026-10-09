"""Answer the health probes before host validation.

Why middleware and not only a URL: Kubernetes probes hit the pod IP with
``Host: <pod-ip>``, which ``ALLOWED_HOSTS`` rejects with 400, and ``SecurityMiddleware``
would redirect a plain-HTTP probe to HTTPS in stage/prod. Answering here, first in
``MIDDLEWARE``, avoids both without loosening ``ALLOWED_HOSTS`` or exempting paths.

The same paths are also routed to ``common.views.HealthzView`` / ``ReadyzView`` (so they
appear in the OpenAPI schema); both call the functions in ``common.health``.
"""

from django.http import HttpRequest, HttpResponse, JsonResponse

from common.health import liveness, readiness

__all__ = ("HealthCheckMiddleware",)

LIVENESS_PATHS = frozenset({"/healthz", "/healthz/"})
READINESS_PATHS = frozenset({"/readyz", "/readyz/"})


class HealthCheckMiddleware:
    def __init__(self, get_response):
        self.get_response = get_response

    def __call__(self, request: HttpRequest) -> HttpResponse:
        # request.path is taken from PATH_INFO and never triggers Host validation.
        if request.path in LIVENESS_PATHS:
            return JsonResponse(liveness())
        if request.path in READINESS_PATHS:
            payload, status = readiness()
            return JsonResponse(payload, status=status)
        return self.get_response(request)
