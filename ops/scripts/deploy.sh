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
#   ops/scripts/deploy.sh --backend ghcr.io/o/r/backend@sha256:<digest>   # pin by digest
#
# This is what .github/workflows/deploy.yml runs over SSH; `make prod deploy` calls it
# with no arguments. Pinning is persisted in .env, so a later manual `make prod deploy`
# re-applies the same build instead of silently drifting back to :latest.
#
# Trust boundary: the image references arrive from outside (a CI job, an operator) and
# end up in ./.env, which Compose interpolates and which holds every production secret.
# They are therefore validated against the image-reference grammar BEFORE anything is
# written, and written as data — never spliced into a program (no sed/perl expression).
set -euo pipefail
cd "$(dirname "$0")/../.."

COMPOSE="docker compose --project-directory . -f ops/compose/docker-compose.prod.yml"

die() { echo "ERROR: $*" >&2; exit 1; }

# The OCI/Docker reference grammar, spelled out: registry[:port]/path[/path…] followed
# by a tag, a digest, or both. Lowercase repository path (Docker requires it),
# tag = [A-Za-z0-9_][A-Za-z0-9._-]{0,127}, digest = sha256. An explicit tag or digest is
# mandatory: a bare repository would mean a moving :latest. Nothing outside this
# alphabet gets through — no whitespace, newline, quote, `$`, `|` or `;`.
IMAGE_REF_RE='^[a-z0-9]([a-z0-9.-]*[a-z0-9])?(:[0-9]{1,5})?(/[a-z0-9]+((\.|_|__|-+)[a-z0-9]+)*)+(:[A-Za-z0-9_][A-Za-z0-9._-]{0,127}(@sha256:[a-f0-9]{64})?|@sha256:[a-f0-9]{64})$'

validate_image() {  # validate_image FLAG VALUE
    # LC_ALL=C: bracket ranges mean ASCII only, whatever locale the server has. `[[ =~ ]]`
    # matches the whole string (a newline is an ordinary character, not a line break).
    local flag="$1" value="$2" LC_ALL=C
    [[ "$value" =~ $IMAGE_REF_RE ]] ||
        die "$flag: not a valid image reference (expected registry/path:tag or registry/path@sha256:<digest>)"
}

pin() {  # pin VAR VALUE — replace or append VAR=VALUE in ./.env, atomically
    local var="$1" value="$2" tmp
    # Same directory, so the final `mv` is an atomic rename: a crash mid-write can never
    # leave a truncated .env. `cp -p` first carries over the owner and mode (0600).
    tmp="$(mktemp .env.pin.XXXXXX)"
    # shellcheck disable=SC2064
    trap "rm -f -- '$tmp'" EXIT
    cp -p .env "$tmp"
    # The value travels through the environment and is compared/printed as a plain
    # string: no regex, no interpolation. Every existing `VAR=` line is replaced; the
    # line is appended when there is none.
    PIN_VAR="$var" PIN_VALUE="$value" awk '
        BEGIN { prefix = ENVIRON["PIN_VAR"] "="; line = prefix ENVIRON["PIN_VALUE"] }
        index($0, prefix) == 1 { print line; done = 1; next }
        { print }
        END { if (!done) print line }
    ' .env >"$tmp"
    mv -- "$tmp" .env
    trap - EXIT
    echo "pinned ${var}=${value}"
}

[ -f .env ] || die "./.env not found (see docs/deploy.md)"

backend_image="" frontend_image=""
while [ $# -gt 0 ]; do
    case "$1" in
        --backend|--frontend)
            [ $# -ge 2 ] || die "$1 requires an image reference"
            validate_image "$1" "$2"
            if [ "$1" = "--backend" ]; then backend_image="$2"; else frontend_image="$2"; fi
            shift 2 ;;
        -h|--help)  sed -n '2,15p' "$0"; exit 0 ;;
        *) echo "Unknown argument: $1" >&2; exit 2 ;;
    esac
done

# Every argument is validated before the first write, so a bad second argument cannot
# leave .env half-updated.
[ -z "$backend_image" ]  || pin BACKEND_IMAGE "$backend_image"
[ -z "$frontend_image" ] || pin FRONTEND_IMAGE "$frontend_image"

$COMPOSE pull
$COMPOSE up -d --remove-orphans
# Keep the previous images around for ~3 days so a rollback is a plain re-pin.
docker image prune -f --filter "until=72h" >/dev/null
$COMPOSE ps
