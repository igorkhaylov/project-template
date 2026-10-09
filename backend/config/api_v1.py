"""``/api/v1/`` routing table: one ``include`` per app that exposes endpoints.

Keep the version in the URL. When a breaking change comes, add ``api_v2.py`` next to
this file and mount it in ``config/urls.py``; clients migrate on their own schedule.
"""

from django.urls import include, path

app_name = "v1"

urlpatterns = [
    path("", include("common.urls")),
]
