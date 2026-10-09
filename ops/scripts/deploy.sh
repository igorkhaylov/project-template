#!/usr/bin/env bash
#
# Server-side deploy (pull-only). Updates the pinned image(s) in ./.env, pulls, and
# applies with `up -d`, which recreates ONLY the services whose image changed — so a
# backend deploy never touches the running frontend container and vice versa.
#
#   ops/scripts/deploy.sh                                  # re-apply what .env pins
#   ops/scripts/deploy.sh --backend  ghcr.io/o/r/backend:sha-<sha>
#   ops/scripts/deploy.sh --frontend ghcr.io/o/r/frontend:sha-<sha>
#   ops/scripts/deploy.sh --backend IMG --frontend IMG     # both in one go
#
# This is what .github/workflows/deploy.yml runs over SSH; `make prod deploy` calls it
# with no arguments. Pinning is persisted in .env, so a later manual `make prod deploy`
# re-applies the same build instead of silently drifting back to :latest.
set -euo pipefail
cd "$(dirname "$0")/../.."

COMPOSE="docker compose --project-directory . -f ops/compose/docker-compose.prod.yml"

pin() {  # pin VAR VALUE — replace or append VAR=VALUE in ./.env
    local var="$1" value="$2"
    if grep -qE "^${var}=" .env; then
        perl -pi -e "s|^${var}=.*|${var}=${value}|" .env
    else
        printf '\n%s=%s\n' "$var" "$value" >> .env
    fi
    echo "pinned ${var}=${value}"
}

[ -f .env ] || { echo "ERROR: ./.env not found (see docs/deploy.md)" >&2; exit 1; }

while [ $# -gt 0 ]; do
    case "$1" in
        --backend)  pin BACKEND_IMAGE "$2"; shift 2 ;;
        --frontend) pin FRONTEND_IMAGE "$2"; shift 2 ;;
        -h|--help)  sed -n '2,16p' "$0"; exit 0 ;;
        *) echo "Unknown argument: $1" >&2; exit 2 ;;
    esac
done

$COMPOSE pull
$COMPOSE up -d --remove-orphans
# Keep the previous images around for ~3 days so a rollback is a plain re-pin.
docker image prune -f --filter "until=72h" >/dev/null
$COMPOSE ps
