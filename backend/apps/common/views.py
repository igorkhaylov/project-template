from django.conf import settings

from drf_spectacular.utils import extend_schema
from rest_framework.permissions import AllowAny
from rest_framework.response import Response
from rest_framework.views import APIView

from common.health import liveness, readiness
from common.serializers import HealthSerializer, MetaSerializer, ReadinessSerializer

__all__ = ("HealthzView", "MetaView", "ReadyzView")


class HealthzView(APIView):
    """``GET /healthz/``: liveness probe. No dependencies by design.

    At runtime ``common.middleware.HealthCheckMiddleware`` answers this path before the
    URL resolver (so probes work with any ``Host`` header); the view documents the
    contract and is the fallback if the middleware is removed.
    """

    authentication_classes = ()
    permission_classes = (AllowAny,)

    @extend_schema(responses=HealthSerializer, summary="Liveness probe", tags=["health"])
    def get(self, request):
        return Response(liveness())


class ReadyzView(APIView):
    """``GET /readyz/``: readiness probe — database and cache reachable, else 503.

    Same middleware note as ``HealthzView``.
    """

    authentication_classes = ()
    permission_classes = (AllowAny,)

    @extend_schema(
        responses={200: ReadinessSerializer, 503: ReadinessSerializer},
        summary="Readiness probe",
        tags=["health"],
    )
    def get(self, request):
        payload, status = readiness()
        return Response(payload, status=status)


class MetaView(APIView):
    """``GET /api/v1/meta/``: app name, deployed version, environment and languages.

    Public on purpose: the SPA calls it first to label the build it is talking to, and
    it doubles as the end-to-end example of the API contract flow (DRF view ->
    drf-spectacular schema -> api/openapi.yaml -> generated TypeScript types).
    """

    authentication_classes = ()
    permission_classes = (AllowAny,)

    @extend_schema(responses=MetaSerializer, summary="Build and runtime metadata")
    def get(self, request):
        data = {
            "name": settings.APP_NAME,
            "version": settings.APP_VERSION,
            "environment": settings.ENVIRONMENT,
            "languages": [{"code": code, "name": str(name)} for code, name in settings.LANGUAGES],
        }
        return Response(MetaSerializer(data).data)
