from django.conf import settings
from django.conf.urls.i18n import i18n_patterns
from django.contrib import admin
from django.urls import include, path
from django.utils.translation import gettext_lazy as _

from drf_spectacular.views import SpectacularAPIView, SpectacularSwaggerView

from common.views import HealthzView, ReadyzView

APP_NAME = settings.APP_NAME

admin.site.site_title = _("%(app_name)s site admin") % {"app_name": APP_NAME}
admin.site.site_header = _("%(app_name)s administration") % {"app_name": APP_NAME}
admin.site.index_title = _("Site administration")
admin.site.enable_nav_sidebar = True
admin.site.empty_value_display = "-"

# Every path below is proxied to the backend by the edge (ops/nginx/*.conf in Compose,
# the Ingress in Kubernetes) and by the Vite dev proxy (frontend/vite.config.ts). Adding
# a new top-level prefix here means adding it there too; everything else is the SPA.
urlpatterns = [
    # Health probes. At runtime common.middleware.HealthCheckMiddleware answers these
    # before URL resolution (and before Host validation); the routes put them in the
    # OpenAPI schema and are the fallback if the middleware is removed.
    path("healthz/", HealthzView.as_view(), name="healthz"),
    path("readyz/", ReadyzView.as_view(), name="readyz"),
    path("api/v1/", include("config.api_v1")),
    path("api/schema/", SpectacularAPIView.as_view(), name="schema"),
    path("api/docs/", SpectacularSwaggerView.as_view(url_name="schema"), name="docs"),
]

urlpatterns += i18n_patterns(
    path("admin/", admin.site.urls),
)


# Keyed on INSTALLED_APPS (dev.py adds the app), not on ENVIRONMENT: importing the
# toolbar registers its models, which fails unless the app is installed.
if "debug_toolbar" in settings.INSTALLED_APPS:
    from debug_toolbar.toolbar import debug_toolbar_urls

    urlpatterns += debug_toolbar_urls()

if "rosetta" in settings.INSTALLED_APPS:
    urlpatterns += [path("rosetta/", include("rosetta.urls"))]
