"""The API is closed by default; public endpoints are an explicit, reviewed list.

``REST_FRAMEWORK["DEFAULT_PERMISSION_CLASSES"]`` is ``IsAuthenticated``, so a view that
forgets ``permission_classes`` is not reachable anonymously. The tests below keep it that
way: one pins the default, the other walks every routed DRF view and fails when the set
of anonymously reachable routes differs from ``PUBLIC_API_ROUTES``.
"""

from django.urls import URLPattern, URLResolver, get_resolver

import pytest
from rest_framework.response import Response
from rest_framework.test import APIRequestFactory
from rest_framework.views import APIView

# Every DRF route that answers without authentication, by URL name (with namespace).
# Adding a name here is a security decision: do it in the same change that sets
# `permission_classes = (AllowAny,)` on the view, so both show up in one review.
PUBLIC_API_ROUTES = {
    "healthz",  # liveness probe (orchestrator)
    "readyz",  # readiness probe (orchestrator)
    "v1:meta",  # build metadata the SPA reads before anything else
}


def _iter_api_routes(patterns=None, namespace=""):
    """Yield ``(route_name, callback)`` for every routed DRF view, recursing into includes."""
    for entry in get_resolver().url_patterns if patterns is None else patterns:
        if isinstance(entry, URLResolver):
            nested = ":".join(part for part in (namespace, entry.namespace) if part)
            yield from _iter_api_routes(entry.url_patterns, nested)
        elif isinstance(entry, URLPattern):
            view_class = getattr(entry.callback, "cls", None)
            if view_class is not None and issubclass(view_class, APIView):
                # An unnamed route is identified by its pattern, so it can never hide.
                name = entry.name or str(entry.pattern)
                yield ":".join(part for part in (namespace, name) if part), entry.callback


def _allows_anonymous(callback) -> bool:
    """True when at least one method of the view passes its permissions without a user.

    Behavioural on purpose: it asks the permission objects instead of looking for
    ``AllowAny``, so ``IsAuthenticatedOrReadOnly`` or a custom class count as public too.
    """
    factory = APIRequestFactory()
    actions = getattr(callback, "actions", None) or {}  # ViewSets: {"get": "list", ...}
    view = callback.cls(**getattr(callback, "initkwargs", {}))
    if actions:
        # What ViewSetMixin.as_view() sets per request; initialize_request() derives
        # `view.action` from it, which per-action get_permissions() overrides rely on.
        view.action_map = actions
    methods = list(actions) or [m.lower() for m in view.allowed_methods if m != "OPTIONS"]
    for method in methods:
        request = view.initialize_request(getattr(factory, method)("/"))
        view.request = request
        if all(permission.has_permission(request, view) for permission in view.get_permissions()):
            return True
    return False


def test_api_is_closed_by_default(settings):
    """A view that declares no permissions must reject an anonymous request."""
    assert settings.REST_FRAMEWORK["DEFAULT_PERMISSION_CLASSES"] == ("rest_framework.permissions.IsAuthenticated",)

    class UndeclaredView(APIView):
        def get(self, request):
            return Response({"leaked": True})

    response = UndeclaredView.as_view()(APIRequestFactory().get("/"))
    # 403 while no authentication scheme is configured; 401 once one that sends a
    # WWW-Authenticate challenge (JWT, token) is enabled.
    assert response.status_code in (401, 403)
    assert "leaked" not in response.data


def test_public_api_routes_are_exactly_the_reviewed_list():
    """Opening (or closing) an endpoint must be reflected in PUBLIC_API_ROUTES."""
    public = {name for name, callback in _iter_api_routes() if _allows_anonymous(callback)}
    assert public == PUBLIC_API_ROUTES, (
        "The set of anonymously reachable API routes changed. If that is intended, update "
        "PUBLIC_API_ROUTES in this file in the same change; otherwise restore the "
        f"permission classes. Unexpectedly public: {sorted(public - PUBLIC_API_ROUTES)}; "
        f"listed but not public: {sorted(PUBLIC_API_ROUTES - public)}."
    )


@pytest.mark.django_db
@pytest.mark.parametrize("path", ["/api/schema/", "/api/docs/"])
def test_schema_and_docs_require_staff(client, path):
    assert client.get(path).status_code in (401, 403)
