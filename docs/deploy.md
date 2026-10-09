# Deploy runbook: zero → first deploy → CI

How to take a server from nothing to a running stack on Docker Compose, and then let CI
deploy to it. (Kubernetes: [../ops/k8s/README.md](../ops/k8s/README.md).)

**The model:** CI builds two images and pushes them to **GHCR**
(`ghcr.io/<owner>/<repo>/backend` and `/frontend`); the server **only pulls**. The server
holds three things: a git checkout of this repo (compose files, nginx edge config,
scripts), its own `./.env` (pins `BACKEND_IMAGE` and `FRONTEND_IMAGE`), and a Docker
login to the registry.

---

## 1. Create a registry pull token (GHCR_PAT)

GHCR packages are **private by default**, so the server cannot pull anonymously. Create
a GitHub **Personal Access Token (classic)** with **only** the `read:packages` scope
(GitHub → Settings → Developer settings → Personal access tokens → Tokens (classic)).
Use a classic token: GHCR does not accept fine-grained tokens for package pulls. It
lives on the server, so keep it read-only and rotate it on a schedule.

```bash
echo "$GHCR_PAT" | docker login ghcr.io -u <github-username> --password-stdin
```

Docker stores it base64-encoded (not encrypted) in `~/.docker/config.json` — one more
reason for `read:packages` only. To rotate: new token, re-run `docker login`, delete the
old one.

## 2. Prepare the server

- Docker Engine ≥ 20.10 with the Compose plugin, `make`, `git`.
- A deploy user that can run `docker` (member of the `docker` group).
- An **external reverse proxy** (host nginx/Caddy/Traefik) that terminates TLS for your
  domain and forwards to `127.0.0.1:APP_PORT` (default `8050`), setting
  `X-Forwarded-Proto: https`, `X-Forwarded-For` and `Host`. The stack's own nginx does
  **not** set `X-Forwarded-Proto` (it would overwrite yours and cause a redirect loop).
- Managed S3/MinIO with a bucket for static+media (static is served from there, not by
  nginx); note both the API endpoint and the public URL.

```bash
sudo mkdir -p /srv/<project> && sudo chown $USER /srv/<project>
git clone git@github.com:<owner>/<repo>.git /srv/<project>
cd /srv/<project>
cp .env.example .env && chmod 600 .env
```

## 3. Configure `./.env` (prod values)

| Variable | Set to |
|---|---|
| `ENVIRONMENT` | `prod` (or `stage`) — derives `DEBUG=False` and every security flag |
| `PROJECT_NAME`, `APP_PORT` | project slug; the port the external proxy forwards to |
| `DJANGO_SECRET_KEY` | `openssl rand -hex 64` (≥ 50 chars, enforced) |
| `DJANGO_ALLOWED_HOSTS` | your real domain(s) only — probes need no entries |
| `DJANGO_CSRF_TRUSTED_ORIGINS`, `DJANGO_CORS_ALLOWED_ORIGINS` | `https://your.domain` (CORS matters only if `APP_API_BASE_URL` points elsewhere) |
| `DJANGO_SUPERUSER_USERNAME` / `_PASSWORD` | the first admin; a placeholder **fails the release step** in stage/prod |
| `POSTGRES_DB` / `USER` / `PASSWORD` | strong password; these also provision the `db` container |
| `DJANGO_MINIO_ENDPOINT` | server-side S3 API endpoint of your managed storage |
| `DJANGO_MINIO_CUSTOM_URL` | **public** base URL of that storage (scheme + host only; bucket appended) |
| `DJANGO_MINIO_BUCKET_NAME` / `ACCESS_KEY` / `SECRET_KEY` | the bucket and app credentials |
| `MINIO_ROOT_USER` / `MINIO_ROOT_PASSWORD` | anything but `minioadmin` → signals "external storage" (`make minio` does nothing) |
| `BACKEND_IMAGE`, `FRONTEND_IMAGE` | `ghcr.io/<owner>/<repo>/backend:sha-<full-sha>` / `…/frontend:sha-<full-sha>` (pins; `deploy.sh` rewrites them) |
| `APP_API_BASE_URL` | leave empty (same origin) |
| `COMPOSE_PROFILES` | `backup` to enable scheduled DB backups ([backup.md](backup.md)) |

## 4. First deploy by hand

```bash
make prod deploy        # = ops/scripts/deploy.sh: pull both images, up -d (release → backend/celery/beat, frontend, nginx)
make prod ps            # backend "healthy", frontend "healthy", release "exited (0)"
make prod logs release  # migrations, collectstatic, superuser
curl -s http://localhost:8050/healthz/        # {"status": "ok"}
curl -s http://localhost:8050/readyz/         # {"status": "ok", "checks": {...}}
curl -s http://localhost:8050/api/v1/meta/    # name, version, environment
curl -sI http://localhost:8050/ | head -1     # 200, the SPA shell
```

If `backend` never becomes healthy, the `release` service failed first: read its logs.
Typical causes: bucket missing/unreachable (`wait_for_storage` fails fast with the
reason), placeholder superuser password, weak secret, Postgres not ready yet.

Through the external proxy: `https://your.domain/` (SPA), `/en/admin/`, `/api/docs/`.

## 5. Let CI deploy (GitHub Actions)

`.github/workflows/deploy.yml` SSHes into the server and runs
`ops/scripts/deploy.sh --backend <image>` and/or `--frontend <image>`: it pins the new
image in `.env`, pulls, and `up -d` recreates only the services whose image changed.

Create GitHub **Environments** `prod` (and `dev`) with these secrets:

| Secret | Value |
|---|---|
| `SSH_HOST`, `SSH_USER`, `SSH_PORT` | the server and the deploy user |
| `SSH_KEY` | private key of a **dedicated** deploy keypair (public key in the deploy user's `authorized_keys`) |
| `SSH_FINGERPRINT` | `ssh-keyscan -p <port> <host> \| ssh-keygen -lf -` → the SHA256 fingerprint (host-key pinning) |
| `DEPLOY_PATH` | `/srv/<project>` |
| `GHCR_USER`, `GHCR_PAT` | the GitHub user and the `read:packages` token from step 1 |

Then:

- **Manual:** Actions → Deploy → Run workflow → environment + `backend_tag` and/or
  `frontend_tag` (`latest`, `vX.Y.Z` or `sha-<full-sha>`; empty = unchanged).
- **Automatic on merge:** set the repository **variable** `AUTO_DEPLOY=true`. After the
  `Backend` or `Frontend` workflow succeeds on `master`, Deploy pins that component to
  the exact `sha-<full-sha>` just built. Unset (the template default) the auto job is
  *skipped*, not failed.

The server's `.env` is never written by CI (an opt-in snippet for that is at the bottom
of `deploy.yml`). The deploy does `git reset --hard` to the deployed commit to sync
compose files, nginx config and scripts; `.env` is gitignored and untouched.

## 6. Day 2

```bash
make prod deploy                                   # re-apply what .env pins (e.g. after a server reboot)
ops/scripts/deploy.sh --backend ghcr.io/<owner>/<repo>/backend:sha-<previous-sha>   # rollback = re-pin
make prod release                                  # re-run migrations/collectstatic by hand
make prod logs backend                             # JSON logs; `docker compose … logs` rotates at 10 MB × 5
make prod dump                                     # DB dump (+ "media"); see backup.md
```

Images are kept for ~3 days after a deploy (`docker image prune --filter until=72h`), so
a rollback to the previous sha is a local re-tag, not a pull. Migrations are
forward-only: write them backward-compatible with the previous code when you want
rollbacks to be safe.

## GitLab CI

Not shipped yet. The same model applies: per-component jobs with `rules: changes:`
(`backend/**`, `frontend/**`, `api/openapi.yaml`), images in the GitLab Container
Registry (`registry.gitlab.com/<group>/<project>/backend`), the server authenticating
with a project **Deploy Token** (`read_registry`) instead of a GHCR PAT, and the deploy
job SSHing to run the same `ops/scripts/deploy.sh`.
