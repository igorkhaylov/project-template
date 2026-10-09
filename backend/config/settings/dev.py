"""Development-only settings (debug toolbar, etc.).

The toolbar comes from the dev dependency group, which the production image does not
install. `make up` (the local production-like stack) runs that image with the same
ENVIRONMENT=dev .env, so the toolbar is enabled only when it is actually importable.
"""

from importlib.util import find_spec

from .base import INSTALLED_APPS, MIDDLEWARE

if find_spec("debug_toolbar") is not None:
    INSTALLED_APPS = [
        *INSTALLED_APPS,
        "debug_toolbar",
    ]

    MIDDLEWARE = [
        "debug_toolbar.middleware.DebugToolbarMiddleware",
        *MIDDLEWARE,
    ]

DEBUG_TOOLBAR_CONFIG = {
    "SHOW_TOOLBAR_CALLBACK": lambda request: True,
}

DEBUG_TOOLBAR_PANELS = [
    "debug_toolbar.panels.history.HistoryPanel",
    "debug_toolbar.panels.versions.VersionsPanel",
    "debug_toolbar.panels.timer.TimerPanel",
    "debug_toolbar.panels.settings.SettingsPanel",
    "debug_toolbar.panels.headers.HeadersPanel",
    "debug_toolbar.panels.request.RequestPanel",
    "debug_toolbar.panels.sql.SQLPanel",
    "debug_toolbar.panels.staticfiles.StaticFilesPanel",
    "debug_toolbar.panels.templates.TemplatesPanel",
    "debug_toolbar.panels.cache.CachePanel",
    "debug_toolbar.panels.signals.SignalsPanel",
    "debug_toolbar.panels.redirects.RedirectsPanel",
]
