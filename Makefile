# Usage:
#   make init               # FIRST RUN: .env + secrets, MinIO bucket, dev stack, migrate, collectstatic, npm ci
#   make dev up             # start the development stack (containers up; backend idle)
#   make dev run            # run the Django dev server (autoreload) -> API at APP_PORT
#   make fe-dev             # run the Vite dev server on the host -> SPA at :5173 (and at APP_PORT via nginx)
#   make up                 # local production-like stack (builds both images, release step, gunicorn)
#   make prod deploy        # SERVER: pull the pinned registry images and (re)start (no build)
#   make api-schema         # regenerate api/openapi.yaml + frontend/src/shared/api/schema.d.ts
#   make dev makemigrations # run a manage.py command in the dev stack
#   make dev logs backend   # tail logs of a service
#   make minio              # provision bucket on the SHARED local MinIO (host service)
#
# Layout: backend/ and frontend/ are self-contained (own Dockerfile, own tooling);
# ops/ holds everything that composes them (compose files, nginx edge, scripts).
# Compose always runs with `--project-directory .` so paths resolve from the repo root.
#
# Prefix selects the compose file:
#   dev  -> ops/compose/docker-compose.dev.yml   (backend/ bind-mounted; backend idles)
#   prod -> ops/compose/docker-compose.prod.yml  (pulls prebuilt images; never builds)
#   none -> ops/compose/docker-compose.yml       (local, builds from source)

COMPOSE_BASE := docker compose --project-directory .
ifneq ($(filter dev,$(MAKECMDGOALS)),)
  COMPOSE := $(COMPOSE_BASE) -f ops/compose/docker-compose.dev.yml
else ifneq ($(filter prod,$(MAKECMDGOALS)),)
  COMPOSE := $(COMPOSE_BASE) -f ops/compose/docker-compose.prod.yml
else
  COMPOSE := $(COMPOSE_BASE) -f ops/compose/docker-compose.yml
endif
DEV_COMPOSE  := $(COMPOSE_BASE) -f ops/compose/docker-compose.dev.yml
TEST_COMPOSE := $(COMPOSE_BASE) -f ops/compose/docker-compose.test.yml

# Extra args: MAKECMDGOALS minus "dev"/"prod" and the target name ($@).
ARGS = $(filter-out dev prod $@,$(MAKECMDGOALS))

# Every real target — used for .PHONY and for the typo guard below.
KNOWN_TARGETS := help init up run down down-v build pull deploy release ps logs shell dbshell \
        migrate makemigrations makemessages compilemessages collectstatic \
        createsuperuser test lint format pre-commit-install minio flush-cache \
        flush-redis dump restore bash bash-db bash-nginx api-schema \
        fe-install fe-dev fe-lint fe-typecheck fe-test fe-build fe-types fe-format fe-check

.PHONY: dev prod $(KNOWN_TARGETS)

# Typo guard: the first goal after the dev/prod prefix must be a real target. Without
# this the catch-all `%:` at the bottom silently swallows typos (`make dev migrat`
# would exit 0 doing nothing). Extra words AFTER a real target (`make logs backend`,
# `make restore dumps/<ts>`) still pass through the catch-all as arguments.
PRIMARY_GOAL := $(firstword $(filter-out dev prod,$(MAKECMDGOALS)))
ifneq ($(PRIMARY_GOAL),)
  ifeq ($(filter $(PRIMARY_GOAL),$(KNOWN_TARGETS)),)
    $(error Unknown target '$(PRIMARY_GOAL)' — run 'make help' for the list)
  endif
endif

help:
	@echo "First run:   make init    # .env + secrets, MinIO bucket, dev stack, migrate, collectstatic, npm ci"
	@echo "Backend (prefix 'dev' = development stack, 'prod' = pull-based deploy, none = local prod-like):"
	@echo "  dev up      then  dev run        # start stack, then serve (autoreload) at APP_PORT"
	@echo "  up / down / down-v / build / ps / logs [service] / release"
	@echo "  prod pull / prod deploy          # server: pull the pinned images and (re)start"
	@echo "  shell dbshell bash bash-db bash-nginx"
	@echo "  migrate makemigrations makemessages compilemessages collectstatic createsuperuser"
	@echo "  test lint format pre-commit-install"
	@echo "  minio flush-cache flush-redis dump restore"
	@echo "Frontend (runs on the host, no prefix):"
	@echo "  fe-install fe-dev fe-lint fe-typecheck fe-test fe-build fe-types fe-format fe-check"
	@echo "API contract:"
	@echo "  api-schema                       # backend -> api/openapi.yaml -> frontend/src/shared/api/schema.d.ts"

dev:
	@:

prod:
	@:

# --- First-time setup ---
# One command from a fresh clone to a migrated dev stack: create .env with generated
# secrets (never overwrites an existing one), provision the shared MinIO bucket, start
# the DEV stack, apply migrations, upload static files to the bucket (static is served
# from S3/MinIO even in dev — without collectstatic the admin renders unstyled), and
# install the frontend's node modules when npm is available. Safe to re-run.
# Then: `make dev createsuperuser`, `make dev run`, `make fe-dev`.
init:
	./ops/scripts/init_env.sh
	./ops/scripts/ensure_minio.sh
	$(DEV_COMPOSE) up -d --build
	$(DEV_COMPOSE) exec backend python manage.py migrate
	$(DEV_COMPOSE) exec backend python manage.py collectstatic --no-input
	@if command -v npm >/dev/null 2>&1; then cd frontend && npm ci; \
	else echo "npm not found — skipping frontend deps (install Node 24+, then: make fe-install)"; fi
	@echo ""
	@echo "Done. Next steps:"
	@echo "  make dev createsuperuser    # create your admin account"
	@echo "  make dev run                # API + admin -> http://localhost:8050 (APP_PORT)"
	@echo "  make fe-dev                 # SPA -> http://localhost:5173 (also proxied at APP_PORT)"

# --- Docker lifecycle ---
up:
	$(COMPOSE) up -d --build

# Dev only: run the Django dev server in the foreground (autoreload) inside the
# already-running backend container. Reachable via nginx at http://localhost:$APP_PORT.
# Run `make dev up` first. Ctrl-C stops the server; the stack keeps running.
run:
	$(COMPOSE) exec backend python manage.py runserver 0.0.0.0:8000

down:
	$(COMPOSE) down

down-v:
	$(COMPOSE) down -v

build:
	$(COMPOSE) build

pull:
	$(COMPOSE) pull

ps:
	$(COMPOSE) ps

# Server-side deploy: pull the pinned images from the registry and (re)start.
# Usage on the server:  make prod deploy
# Pin a build first with ops/scripts/deploy.sh --backend <image> (what CI does).
deploy:
	./ops/scripts/deploy.sh

# Re-run the release step (migrate + collectstatic + first superuser) by hand. `up`
# runs it automatically before starting backend; the dev stack uses `make dev migrate`.
release:
	$(COMPOSE) run --rm release

logs:
	$(COMPOSE) logs -f $(ARGS)

# --- Django management ---
shell:
	$(COMPOSE) exec backend python manage.py shell

dbshell:
	$(COMPOSE) exec db psql -U $${POSTGRES_USER:-app} -d $${POSTGRES_DB:-app}

migrate:
	$(COMPOSE) exec backend python manage.py migrate

makemigrations:
	$(COMPOSE) exec backend python manage.py makemigrations

makemessages:
	$(COMPOSE) exec backend python manage.py makemessages -l ru -l en --ignore .venv

compilemessages:
	$(COMPOSE) exec backend python manage.py compilemessages

collectstatic:
	$(COMPOSE) exec backend python manage.py collectstatic --no-input

createsuperuser:
	$(COMPOSE) exec backend python manage.py createsuperuser

# --- Quality (backend) ---
test:
	$(COMPOSE) exec backend pytest

lint:
	$(COMPOSE) exec backend ruff check .

format:
	$(COMPOSE) exec backend ruff format .

pre-commit-install:
	pre-commit install

# --- API contract ---
# The backend is the source of truth: drf-spectacular renders api/openapi.yaml (always
# from the test image with no .env, so the output is deterministic and CI can diff it),
# then the frontend generates TypeScript types from it. Commit both files together with
# the backend change that caused them — CI fails on either side if they drift.
api-schema:
	$(TEST_COMPOSE) build backend
	$(TEST_COMPOSE) run --rm --no-deps -T backend python manage.py spectacular --validate > api/openapi.yaml
	@echo "wrote api/openapi.yaml"
	cd frontend && npm run api:types

# --- Frontend (host-side; Node 24+) ---
fe-install:
	cd frontend && npm ci

fe-dev:
	cd frontend && npm run dev

fe-lint:
	cd frontend && npm run lint

fe-typecheck:
	cd frontend && npm run typecheck

fe-test:
	cd frontend && npm test

fe-build:
	cd frontend && npm run build

fe-types:
	cd frontend && npm run api:types

fe-format:
	cd frontend && npm run format

# Everything CI runs: typecheck, lint, format:check, tests, production build.
fe-check:
	cd frontend && npm run check

# --- MinIO (provision object storage against the SHARED local MinIO) ---
# Starts the single shared host MinIO if needed, then creates this project's bucket +
# app user + policy. Skips entirely if the project points at external/managed storage.
# Not prefixed with `dev`: it manages a host-level service, independent of the stack.
minio:
	./ops/scripts/ensure_minio.sh

# --- Utilities ---
# Redis layout: db 0 = Celery broker + task results, db 1 = Django cache.
# flush-cache is the safe everyday command; flush-redis wipes EVERYTHING — including
# queued Celery tasks — so reach for it deliberately.
flush-cache:
	$(COMPOSE) exec redis redis-cli -n 1 FLUSHDB

flush-redis:
	$(COMPOSE) exec redis redis-cli FLUSHALL

# Backup / restore (DB + manifest always; add "media" to also dump S3/MinIO media).
# Examples: make dump | make dump media | make dev dump media
#           make restore dumps/<ts> | make dev restore dumps/<ts>
dump:
	COMPOSE="$(COMPOSE)" ./ops/scripts/dump_all.sh $(ARGS)

restore:
	COMPOSE="$(COMPOSE)" ./ops/scripts/restore_all.sh $(ARGS)

# --- Container shells ---
bash:
	$(COMPOSE) exec -it backend bash

bash-db:
	$(COMPOSE) exec -it db bash

bash-nginx:
	$(COMPOSE) exec -it nginx sh

# Catch extra arguments (e.g. `make logs backend`) so make doesn't error on them.
%:
	@:
