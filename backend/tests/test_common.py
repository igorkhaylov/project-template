from datetime import date

from django.core.exceptions import ValidationError

import pytest

from common.generators import generate_dates
from common.utils import Base62
from common.validators import FCM_TOKEN_MAX_LENGTH, validate_fcm_token


class TestBase62:
    @pytest.mark.parametrize("n", [0, 1, 61, 62, 999, 1_000_000, 2_147_483_647])
    def test_roundtrip(self, n):
        assert Base62.decode(Base62.encode(n)) == n

    def test_invalid_decode_raises(self):
        with pytest.raises(ValueError):
            Base62.decode("!!!")


class TestGenerateDates:
    def test_days(self):
        dates = generate_dates(start_date=date(2026, 1, 1), count=3, unit="days")
        assert dates == [date(2026, 1, 1), date(2026, 1, 2), date(2026, 1, 3)]

    def test_months_uses_relativedelta(self):
        # Regression: months/years previously raised AttributeError (dateutil import).
        dates = generate_dates(start_date=date(2026, 1, 31), count=2, unit="months")
        assert dates[1] == date(2026, 2, 28)

    def test_years(self):
        dates = generate_dates(start_date=date(2024, 2, 29), count=2, unit="years")
        assert dates[1] == date(2025, 2, 28)


class TestValidateFcmToken:
    def test_accepts_realistic_token(self):
        # Real tokens are opaque printable-ASCII strings, typically `instance:APA91b...`.
        validate_fcm_token("dJx3Kf9qR0m:APA91b" + "G7x_Qw-9" * 20)

    @pytest.mark.parametrize(
        "token",
        [
            "",
            "a" * (FCM_TOKEN_MAX_LENGTH + 1),
            "токен-не-ascii",
            "with space",
            "trailing-newline\n",
            "tab\tinside",
        ],
    )
    def test_rejects_garbage(self, token):
        with pytest.raises(ValidationError) as exc_info:
            validate_fcm_token(token)
        assert exc_info.value.code == "invalid_fcm_token"


def test_suite_runs_in_test_environment(settings):
    """Regression: `make dev test` runs inside the dev container, whose environment carries
    ENVIRONMENT=dev from .env. The test settings must still force ENVIRONMENT=test, or
    DEBUG flips on and urls.py tries to mount the debug toolbar without its app installed
    (RuntimeError on the first request)."""
    assert settings.ENVIRONMENT == "test"
    assert settings.DEBUG is False
    assert "debug_toolbar" not in settings.INSTALLED_APPS


@pytest.mark.django_db
def test_migrations_in_sync():
    """The suite runs with --no-migrations, so nothing else would notice a model change that
    was never turned into a migration — until `migrate` in the entrypoint silently skips it."""
    from io import StringIO

    from django.core.management import call_command

    out = StringIO()
    try:
        call_command("makemigrations", "--check", "--dry-run", stdout=out, stderr=out)
    except SystemExit as exc:  # makemigrations --check exits 1 when a migration is missing
        pytest.fail(f"Models and migrations are out of sync (exit {exc.code}):\n{out.getvalue()}")


# --- health probes and the API contract ---------------------------------------------


def test_healthz_is_answered_before_host_validation(client, settings):
    """Kubernetes probes arrive with the pod IP as Host; the liveness endpoint must not
    depend on ALLOWED_HOSTS (nor on the database)."""
    settings.ALLOWED_HOSTS = ["example.com"]
    resp = client.get("/healthz/", HTTP_HOST="10.0.0.5:8000")
    assert resp.status_code == 200
    assert resp.json() == {"status": "ok"}


@pytest.mark.django_db
def test_readyz_reports_dependencies(client):
    resp = client.get("/readyz/")
    assert resp.status_code == 200
    assert resp.json() == {"status": "ok", "checks": {"database": "ok", "cache": "ok"}}


@pytest.mark.django_db
def test_health_views_match_the_middleware(rf):
    """The routed views are the documented contract; they must return exactly what the
    middleware answers at runtime, since the middleware short-circuits them."""
    from common.views import HealthzView, ReadyzView

    healthz = HealthzView.as_view()(rf.get("/healthz/"))
    assert healthz.status_code == 200
    assert healthz.data == {"status": "ok"}

    readyz = ReadyzView.as_view()(rf.get("/readyz/"))
    assert readyz.status_code == 200
    assert readyz.data == {"status": "ok", "checks": {"database": "ok", "cache": "ok"}}


def test_openapi_schema_documents_health_and_meta():
    """Guard the contract: the paths the frontend/orchestrator rely on stay in the schema."""
    from drf_spectacular.generators import SchemaGenerator

    schema = SchemaGenerator().get_schema(request=None, public=True)
    assert {"/healthz/", "/readyz/", "/api/v1/meta/"} <= set(schema["paths"])
    assert "HealthStateEnum" in schema["components"]["schemas"]


@pytest.mark.django_db
def test_meta_endpoint_is_public(client, settings):
    resp = client.get("/api/v1/meta/")
    assert resp.status_code == 200
    body = resp.json()
    assert body["name"] == settings.APP_NAME
    assert body["version"] == settings.APP_VERSION
    assert body["environment"] == "test"
    assert [lang["code"] for lang in body["languages"]] == ["en", "ru"]
