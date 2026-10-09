# Adapting this template to a new project

Two kinds of work: the **mechanical renames**, which one script does, and the
**decisions**, which it cannot make for you. Do both before the first release — renaming
a bucket, a database or a registry image later means migrating data.

## 0. The mechanical part: `scripts/new_project.sh`

```bash
# GitHub → "Use this template" → clone, then:
scripts/new_project.sh                                   # derives names from `git remote origin`
scripts/new_project.sh --slug acme-shop --owner acme --name "Acme Shop"   # or explicit
git diff && git commit -am "[INIT] start acme-shop from project-template"
make init
```

What it rewrites, consistently, everywhere (compose files, `.env.example`, settings,
`pyproject.toml` + `uv.lock`, `package.json` + lockfile, `index.html`, docs):

| Template identifier | Becomes | Used for |
|---|---|---|
| `igorkhaylov/project-template` | `<owner>/<repo>` | `ghcr.io/<owner>/<repo>/{backend,frontend}` image defaults |
| `project-template` | `<slug>` | Compose project name (containers, volumes, network), MinIO bucket/user, package names |
| `project_template` | `<slug>` with `_` | Postgres database and user |
| `ProjectTemplate` | PascalCase slug | `DJANGO_APP_NAME` (admin titles, API title), `<title>` |
| `Project Template` | `--name` or title-cased slug | README heading |
| `8050` (`APP_PORT`) | `--port` or a stable hash of the slug in 8100-8999 | the stack's host port in `.env.example`, compose defaults, the Vite proxy target and docs — distinct per project, so clones on one machine do not collide |

It is idempotent and never touches `.env`, `.git`, `node_modules`. If you had already run
`make init`, delete `.env` and run it again (it never overwrites an existing `.env`), or
edit `PROJECT_NAME` / `APP_PORT` / `POSTGRES_*` / `MINIO_*` by hand.

The one URL it leaves alone on purpose: the `django-stdimage` fork in
`backend/pyproject.toml` is a dependency, not a template identifier.

## 1. Decisions: repository

| Where | Decide |
|---|---|
| `CODEOWNERS` | replace `@OWNER/backend-team` / `@OWNER/frontend-team` with real teams or users |
| `LICENSE` | the template is MIT with the author's copyright line |
| `README.md` | first paragraph; keep the operational sections, they stay true |
| `.github/workflows/deploy.yml` | GitHub Environments `prod` / `dev` with the SSH + GHCR secrets ([deploy.md](deploy.md)); set the repo variable `AUTO_DEPLOY=true` when you want deploy-on-merge (until then the auto job shows as *skipped*, which is expected) |
| `.vscode/settings.json` | optional: spell-check dictionary only |

## 2. Decisions: backend settings

| Setting | File | Template default |
|---|---|---|
| `TIME_ZONE` | `backend/config/settings/base.py` | `Asia/Tashkent` |
| `LANGUAGE_CODE`, `LANGUAGES`, `MODELTRANSLATION_*` | `base.py` | `en` default + `ru`; keep `modeltranslation` first in `INSTALLED_APPS`. Changing the language set also changes the `(en\|ru)` prefix in `ops/nginx/*.conf` and `frontend/vite.config.ts` |
| `REST_FRAMEWORK` | `third_party.py` | **no** `DEFAULT_PERMISSION_CLASSES`, empty `DEFAULT_AUTHENTICATION_CLASSES`: every endpoint you add is world-open until you set `IsAuthenticated` + an auth class (session, JWT, …). `MetaView` is explicitly `AllowAny`. |
| `SPECTACULAR_SETTINGS` (`DESCRIPTION`, `VERSION`, `SERVE_PERMISSIONS`) | `third_party.py` | placeholder description; Swagger UI requires admin login |
| `DATA_UPLOAD_MAX_MEMORY_SIZE` / `FILE_UPLOAD_MAX_MEMORY_SIZE` | `base.py` | 10 MB; the edge allows 500 MB bodies on backend paths (`client_max_body_size`) |
| Celery limits, queues, concurrency | `backend/config/celery.py`, compose `celery` command | 3 h task limit, single `celery` queue, 2 processes |
| `GUNICORN_WORKERS` | `.env` | 2 — scale by replicas |

## 3. Decisions: the user model

`users.User` is a custom `AbstractBaseUser` (username login, optional verified emails in
`UserEmail`). Before the first release:

- **Activation.** `is_active` defaults to `False`; nothing in the template activates a
  regular user (intended trigger: OTP/email verification, marked `TODO(OTP)` in
  `users/models.py`). Implement the flow or flip the default.
- **Fields.** Add/remove, then `make dev makemigrations`. To start from a single clean
  initial migration, delete `0001_initial.py`, regenerate it, `make dev down-v` — only
  before the first deploy. `test_migrations_in_sync` fails the suite on any drift.

## 4. Decisions: frontend

| Where | Decide |
|---|---|
| `frontend/index.html`, `public/favicon.svg` | title (already renamed) and icon |
| `frontend/src/App.tsx` | replace the starter screen; keep calls going through `src/api/client.ts` |
| libraries | router, data cache, CSS framework, i18n — none are preinstalled ([frontend/README.md](../frontend/README.md)) |
| Vite SPA vs Next.js | the default is a static SPA; the Next.js variant is documented in [frontend/README.md](../frontend/README.md#running-a-nextjs-frontend-instead) |
| `APP_API_BASE_URL` | keep empty (same origin). Set it only if the API is served from a different host — then also set `DJANGO_CORS_ALLOWED_ORIGINS` |

## 5. Optional features (off by default)

| Feature | How to turn on |
|---|---|
| Firebase push notifications | `firebase-admin` is an extra: `uv sync --extra push`, add `--extra push` to every `uv sync` in `backend/Dockerfile` and `Dockerfile.dev`, put the service-account JSON in `firebase_credentials/` (git- and docker-ignored), import `common.firebase` once at startup |
| Scheduled DB backups (prod) | `COMPOSE_PROFILES=backup` in the server's `.env` ([backup.md](backup.md)) |
| WebSockets through the edge | commented `location /ws/` block in `ops/nginx/nginx.conf`; add `ws` to the prefix lists |
| Debug toolbar | on in `ENVIRONMENT=dev` when the dev dependency group is installed; `/__debug__/` |
| GitLab CI | not shipped; the GitHub workflows translate 1:1 (`rules: changes:` per component, GitLab Container Registry, Deploy Token for the server) |

## 6. Things to leave alone (they look odd but are deliberate)

- **`ops/nginx/nginx.conf` does not set `X-Forwarded-Proto`.** The external TLS proxy
  does; re-setting it here would create a redirect loop under `SECURE_SSL_REDIRECT`.
- **`/healthz/` and `/readyz/` are middleware, not URLs.** They must answer before
  `ALLOWED_HOSTS` validation (Kubernetes probes send the pod IP as `Host`).
- **Migrations are not in the web process.** `release.sh` runs them once per deploy;
  `entrypoint.sh` only starts gunicorn.
- **`ENVIRONMENT=production` is rejected on purpose.** Only `dev | test | stage | prod`.
- **Static files live in the bucket, even in dev.** No filesystem fallback;
  `collectstatic` is what makes the admin render with CSS.
- **MinIO is not in `ops/compose/*.yml`.** One shared host container serves every
  project (`make minio`); prod points at managed storage.
- **`make dev up` does not serve HTTP.** The backend container idles; `make dev run`
  starts the server. The frontend dev server runs on the host (`make fe-dev`).
- **`api/openapi.yaml` and `frontend/src/api/schema.d.ts` are generated.** Never
  hand-edit; `make api-schema`.
