# Backend (Django + DRF)

Self-contained Django service: this directory is the Docker build context, the uv
project and the pytest root. Day-to-day commands go through the root `Makefile`
(`make dev …`); everything below also works standalone.

```bash
# standalone (no compose): tests + lint on the host
uv sync && uv run pytest && uv run ruff check .
# standalone image
docker build -t backend .
docker run --rm -e ENVIRONMENT=dev -p 8000:8000 backend        # gunicorn on :8000
```

## Structure

```
apps/
  common/          abstract models (UIDMixin, TimestampMixin, RankMixin, BaseModel), utils, validators,
                   health.py (liveness/readiness checks) + HealthCheckMiddleware + HealthzView/ReadyzView,
                   MetaView (/api/v1/meta/),
                   management commands: wait_for_storage · media_dump · media_load · media_info · rewrite_media_urls
  users/           custom User + UserEmail, auth manager, createsuperuserauto, initial migration
config/
  settings/        base.py · third_party.py · dev.py · test.py  (ENVIRONMENT selects)
  urls.py          routes: /api/v1/ (api_v1.py), /api/schema/, /api/docs/, /<lang>/admin/, /rosetta/
  api_v1.py        one include() per app that exposes endpoints
  celery.py · wsgi.py · asgi.py
scripts/
  entrypoint.sh    the image's CMD: gunicorn only
  release.sh       migrate → wait_for_storage → collectstatic → createsuperuserauto (once per deploy)
tests/             pytest suite (sqlite, locmem, eager Celery — no services needed)
locale/            project-level translations (compiled to .mo at image build time)
Dockerfile         multi-stage: builder (uv sync --frozen) → runtime (non-root uid 1000)
Dockerfile.dev     dev image: venv at /opt/venv, source bind-mounted by ops/compose/docker-compose.dev.yml
```

## What you get out of the box

| URL | What | Notes |
|---|---|---|
| `/healthz/` | liveness `{"status":"ok"}` | no dependencies; answered by middleware before `ALLOWED_HOSTS`/HTTPS-redirect; in the OpenAPI schema |
| `/readyz/` | readiness: `{"status":"ok","checks":{"database":"ok","cache":"ok"}}` | 503 when a check fails; Compose healthcheck + k8s readiness; in the OpenAPI schema |
| `/api/v1/meta/` | app name, deployed version, environment, languages | public; the example of the contract flow |
| `/api/schema/` · `/api/docs/` | OpenAPI schema · Swagger UI (dark theme in `templates/drf_spectacular/`) | admin login required (`SPECTACULAR_SETTINGS`) |
| `/en/admin/`, `/ru/admin/` | Django admin (`i18n_patterns`); `/admin/` redirects to the active language | |
| `/rosetta/` | translation UI | superusers and the "Rosetta Users" group |
| `/__debug__/` | debug toolbar | `ENVIRONMENT=dev` and the dev dependency group only |

`REST_FRAMEWORK` sets **no default permission class** and no authentication class: the
next endpoint you add is world-open until you set `IsAuthenticated` and an auth class
(`MetaView` is explicitly `AllowAny`). Decide this in [docs/adapting.md](../docs/adapting.md).

### Adding an endpoint (and keeping the contract)

1. Serializer in `apps/<app>/serializers.py`, view in `views.py`, route in `apps/<app>/urls.py`,
   `include()` it from `config/api_v1.py` (versioned: `/api/v1/<app>/…`).
2. `make api-schema` → commit `api/openapi.yaml` **and** `frontend/src/api/schema.d.ts`.
   CI on both sides fails if either is stale.
3. A new *top-level* prefix (anything other than `/api/…`) must also be added to the
   edge (`ops/nginx/*.conf`) and the dev proxy (`frontend/vite.config.ts`).

## Processes

| Process | Command | Where |
|---|---|---|
| web | `bash scripts/entrypoint.sh` (gunicorn, `GUNICORN_WORKERS` default 2) | image CMD |
| release | `bash scripts/release.sh` | compose `release` service / k8s Job |
| worker | `celery -A config worker --loglevel=INFO --concurrency=2 -Q celery` | compose `celery` |
| beat | `celery -A config beat --loglevel=INFO` | compose `celery-beat`, **one replica** |

Migrations never run in the web process. Translations are compiled by `msgfmt` in the
Dockerfile (no Django needed), so the release step is schema + static only. Periodic
tasks live in the database (`django-celery-beat`, edited in the admin); beat holds no
local state.

## Configuration

Everything comes from environment variables (`python-decouple`; locally from the root
`.env`). `ENVIRONMENT` must be one of `dev | test | stage | prod` and derives `DEBUG` and
every security flag; anything else raises at startup.

| Variable | Default | Description |
|---|---|---|
| `ENVIRONMENT` | `prod` | see above |
| `DJANGO_SECRET_KEY` | dev-only default | **required, ≥ 50 chars in stage/prod** (`openssl rand -hex 64`) |
| `DJANGO_APP_NAME` | `ProjectTemplate` | admin titles, gunicorn process name, API title |
| `APP_VERSION` | `dev` | build identity (baked by CI via the `APP_VERSION` build arg); reported by `/api/v1/meta/` |
| `DJANGO_ALLOWED_HOSTS` | `""` | comma-separated public host names; probes do not need entries here |
| `DJANGO_CSRF_TRUSTED_ORIGINS` / `DJANGO_CORS_ALLOWED_ORIGINS` | `""` | comma-separated, with scheme |
| `DJANGO_LOG_LEVEL` | `INFO` | `DEBUG`/`INFO`/`WARNING`/`ERROR` |
| `GUNICORN_WORKERS` / `GUNICORN_TIMEOUT` / `GUNICORN_GRACEFUL_TIMEOUT` | `2` / `60` / `30` | scale with replicas, not workers |
| `DATABASE_URL` | unset | one connection string; **wins** over `POSTGRES_*` when set (k8s, managed DB) |
| `POSTGRES_DB/USER/PASSWORD/HOST/PORT` | compose defaults | Compose-style fallback; `POSTGRES_CONN_MAX_AGE` 600 (0 behind pgbouncer) |
| `REDIS_URL` | `redis://REDIS_HOST:REDIS_PORT` | base address **without** db number; `/0` broker+results, `/1` cache |
| `DJANGO_MINIO_ENDPOINT` | `http://host.docker.internal:9000` | server-side S3 API endpoint |
| `DJANGO_MINIO_CUSTOM_URL` | `http://localhost:9000` | browser-facing base URL (scheme + host only; bucket appended) |
| `DJANGO_MINIO_BUCKET_NAME` / `ACCESS_KEY` / `SECRET_KEY` | — | this project's bucket + app credentials |
| `DJANGO_SUPERUSER_USERNAME` / `_PASSWORD` | `admin` / — | `createsuperuserauto` in the release step; placeholder ⇒ skipped in dev, error in stage/prod |

### Health probes and `ALLOWED_HOSTS`

The checks live in `common.health`. `common.middleware.HealthCheckMiddleware` is first
in `MIDDLEWARE` and answers `/healthz/` and `/readyz/` before URL resolution, before
`SecurityMiddleware`'s HTTPS redirect and before Django validates the `Host` header. The
same paths are also routed to `HealthzView` / `ReadyzView`, which is how they appear in
`api/openapi.yaml` (and what would serve them if the middleware were removed). That is what lets a Kubernetes
probe (which sends the pod IP as `Host`) and the Compose healthcheck (`localhost`) work
with an `ALLOWED_HOSTS` that lists only the public domain. Liveness checks nothing but
the process on purpose: a DB outage must not make the orchestrator restart every pod.

### Deployment topology

The app **always runs behind an external reverse proxy** that terminates TLS and sets
`X-Forwarded-Proto` (and the real client IP as the first `X-Forwarded-For` hop). Django
trusts that header (`SECURE_PROXY_SSL_HEADER`), so the in-stack nginx **must not re-set
it** — the line is intentionally commented in `ops/nginx/nginx.conf`; re-setting it
would overwrite the edge's value and create a redirect loop under `SECURE_SSL_REDIRECT`.
`common.request.get_ip_from_request` trusts the first `X-Forwarded-For` entry, which is
only safe when that edge rejects client-supplied values.

### Object storage

Static **and** media are served from S3/MinIO; nginx serves no files. Locally a single
shared MinIO container on the host serves every project (`make minio`,
`ops/scripts/ensure_minio.sh`); in stage/prod point `DJANGO_MINIO_*` at managed storage.
Two addresses matter and mixing them up is the classic "uploads work but images 404":

| Variable | Used by | Example |
|---|---|---|
| `DJANGO_MINIO_ENDPOINT` | backend, server-side S3 API | `http://host.docker.internal:9000` |
| `DJANGO_MINIO_CUSTOM_URL` | browser, prefix of every media/static link | `http://localhost:9000` → `http://localhost:9000/<bucket>/media/x.jpg` |

`User.picture` uses `StdImageField` from a maintained fork with default variations
([docs/stdimage.md](../docs/stdimage.md)).

## Logging

`django-structlog` to stdout only. `dev` renders a colorized console; stage/prod emit one
JSON object per line with `request_id` and `user_id` bound to every line.

## Testing

Minimal configuration (`config.settings.test`): sqlite in-memory, locmem cache/email,
eager Celery, in-memory storage — no Postgres/Redis/MinIO. `--no-migrations` builds the
schema from the models; `test_migrations_in_sync` separately asserts
`makemigrations --check` is clean, so a forgotten migration cannot reach CI unnoticed.

```bash
make dev test                      # inside the dev container
uv run pytest                      # on the host (after uv sync)
docker compose --project-directory .. -f ../ops/compose/docker-compose.test.yml up --build --exit-code-from backend   # what CI runs
```

Selecting the test settings **forces `ENVIRONMENT=test`**, so the suite behaves the same
on the host, in the dev container (whose `.env` exports `ENVIRONMENT=dev`) and in CI.

## Code quality

Ruff (`E, F, I, UP, B, C4, SIM, DJ, RUF`, line length 120, migrations excluded) via
`pyproject.toml`; pre-commit hooks at the repo root run `ruff check` and `ruff format`
using the `ruff` on your `PATH` (`uv tool install ruff pre-commit`, then `pre-commit install`).

## Dependencies (uv)

`pyproject.toml` + committed `uv.lock`; images install with `uv sync --frozen`.

```bash
uv add <package>                   # runtime dependency
uv add --dev <package>             # dev group (tests, toolbar, ruff)
uv lock --upgrade-package django   # bump one package
make dev build                     # rebuild the dev image to pick it up
```

Editing `pyproject.toml` by hand without re-locking makes the next image build fail
("lockfile is out of date"). Full reference: [docs/uv.md](../docs/uv.md). Optional
extras: `firebase-admin` behind `--extra push` (see `pyproject.toml`).

## Internationalization

English (default) and Russian via `django-modeltranslation`; `django-rosetta` at
`/rosetta/`. `make dev makemessages` / `make dev compilemessages` in development; the
image compiles `.po` → `.mo` at build time.

## The user model

`users.User` is a custom `AbstractBaseUser` (username login, optional verified emails
in `UserEmail`). **`is_active` defaults to `False`**: only superusers are active out of
the box; a regular user cannot log in until something sets `is_active=True` (the
intended trigger is OTP/email verification, a documented `TODO` in `users/models.py`).
Decide the activation flow before shipping signup.

## Editor setup

```bash
uv sync                            # → .venv (runtime + dev group), for autocomplete, ruff, pyright
```

Point the editor at `backend/.venv/bin/python`; `pyrightconfig.json` and `[tool.ruff]`
are picked up from this directory. The server itself runs inside the container
(`make dev run`); `db`/`redis` ports are not published to the host.
