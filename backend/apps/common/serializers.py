from rest_framework import serializers

from common.health import HEALTH_STATES

__all__ = (
    "HealthSerializer",
    "LanguageSerializer",
    "MetaSerializer",
    "ReadinessChecksSerializer",
    "ReadinessSerializer",
)


class HealthSerializer(serializers.Serializer):
    """``GET /healthz/`` — liveness."""

    status = serializers.ChoiceField(choices=HEALTH_STATES)


class ReadinessChecksSerializer(serializers.Serializer):
    database = serializers.ChoiceField(choices=HEALTH_STATES)
    cache = serializers.ChoiceField(choices=HEALTH_STATES)


class ReadinessSerializer(serializers.Serializer):
    """``GET /readyz/`` — readiness; HTTP 503 when any check is ``error``."""

    status = serializers.ChoiceField(choices=HEALTH_STATES)
    checks = ReadinessChecksSerializer()


class LanguageSerializer(serializers.Serializer):
    code = serializers.CharField()
    name = serializers.CharField()


class MetaSerializer(serializers.Serializer):
    """Public build and runtime facts a client needs before it knows anything else."""

    name = serializers.CharField()
    version = serializers.CharField()
    environment = serializers.CharField()
    languages = LanguageSerializer(many=True)
