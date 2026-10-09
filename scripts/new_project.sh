#!/usr/bin/env bash
#
# Turn a fresh copy of the template into YOUR project in one command.
#
# Rewrites every template identifier — Compose project name, bucket and DB names, image
# names, the app title — consistently across the repo (compose files, .env.example,
# settings, package manifests and lockfiles, docs). Nothing to find-and-replace by hand.
#
#   scripts/new_project.sh                         # derive everything from `git remote origin`
#   scripts/new_project.sh --slug acme-shop --owner acme
#   scripts/new_project.sh --slug acme-shop --owner acme --name "Acme Shop" --port 8120
#
# Derivation from git@github.com:acme/acme-shop.git (or the https form):
#   owner  = acme           GHCR namespace: ghcr.io/acme/acme-shop/{backend,frontend}
#   slug   = acme-shop      Compose project, MinIO bucket/user, package names
#   snake  = acme_shop      Postgres database + user
#   pascal = AcmeShop       DJANGO_APP_NAME, <title>
#   title  = Acme Shop      README heading       (override with --name)
#   port   = 8100-8999      APP_PORT, a stable hash of the slug (override with --port),
#                           so projects on one machine do not all fight over 8050
#
# Idempotent (a second run finds nothing to change) and safe: never touches .env, .git,
# node_modules, lockfiles or virtualenvs. Review the diff, then commit.
set -euo pipefail
cd "$(dirname "$0")/.."

# What the template calls itself. Replaced in this order (most specific first).
T_OWNER_REPO="igorkhaylov/project-template"
T_SLUG="project-template"
T_SNAKE="project_template"
T_PASCAL="ProjectTemplate"
T_TITLE="Project Template"
T_PORT="8050"   # APP_PORT of the template (django-template's default)

slug="" owner="" title="" port=""
while [ $# -gt 0 ]; do
    case "$1" in
        --slug)  slug="$2";  shift 2 ;;
        --owner) owner="$2"; shift 2 ;;
        --name)  title="$2"; shift 2 ;;
        --port)  port="$2";  shift 2 ;;
        -h|--help) sed -n '3,24p' "$0"; exit 0 ;;
        *) echo "Unknown argument: $1 (see --help)" >&2; exit 2 ;;
    esac
done

# --- derive from the git remote when not given -------------------------------------
if [ -z "$slug" ] || [ -z "$owner" ]; then
    remote="$(git remote get-url origin 2>/dev/null || true)"
    if [ -z "$remote" ]; then
        echo "No 'origin' remote and no --slug/--owner given." >&2
        echo "Either push this repo first (GitHub: 'Use this template' -> clone), or pass --slug and --owner." >&2
        exit 1
    fi
    # Works for git@github.com:owner/repo.git, https://github.com/owner/repo(.git)
    # and ssh://git@host/owner/repo.git: repo = last path segment, owner = the one before.
    base="${remote%.git}"
    repo_from="${base##*[:/]}"
    owner_from="${base%/*}"; owner_from="${owner_from##*[:/]}"
    [ -z "$slug" ]  && slug="$repo_from"
    [ -z "$owner" ] && owner="$owner_from"
fi

slug="$(printf '%s' "$slug" | tr '[:upper:]' '[:lower:]')"
owner="$(printf '%s' "$owner" | tr '[:upper:]' '[:lower:]')"
if ! printf '%s' "$slug" | grep -Eq '^[a-z0-9]+(-[a-z0-9]+)*$'; then
    echo "Slug must be lowercase letters, digits and single dashes (got '$slug')." >&2
    exit 1
fi
snake="${slug//-/_}"
pascal="$(printf '%s' "$slug" | awk -F- '{for (i=1;i<=NF;i++) printf "%s%s", toupper(substr($i,1,1)), substr($i,2)}')"
[ -z "$title" ] && title="$(printf '%s' "$slug" | awk -F- '{for (i=1;i<=NF;i++) printf "%s%s%s", (i>1?" ":""), toupper(substr($i,1,1)), substr($i,2)}')"

# APP_PORT: a stable hash of the slug in 8100-8999 (cksum is POSIX, same result on every
# machine), so each project gets its own default and clones agree on it. --port overrides.
if [ -z "$port" ]; then
    port=$(( 8100 + $(printf '%s' "$slug" | cksum | cut -d' ' -f1) % 900 ))
fi
if ! printf '%s' "$port" | grep -Eq '^[0-9]+$' || [ "$port" -lt 1024 ] || [ "$port" -gt 65535 ]; then
    echo "Port must be a number between 1024 and 65535 (got '$port')." >&2
    exit 1
fi

if [ "$slug" = "$T_SLUG" ] && [ "$owner/$slug" = "$T_OWNER_REPO" ]; then
    echo "This already is the template ($T_OWNER_REPO); nothing to do."
    exit 0
fi

echo "owner/repo : $owner/$slug"
echo "slug       : $slug"
echo "snake      : $snake"
echo "pascal     : $pascal"
echo "title      : $title"
echo "APP_PORT   : $port (template: $T_PORT)"
if command -v lsof >/dev/null 2>&1 && lsof -nP -iTCP:"$port" -sTCP:LISTEN >/dev/null 2>&1; then
    echo "             WARNING: something on this machine already listens on $port — re-run with --port <free port>"
fi
echo

# --- files that mention any template identifier (text files only) -------------------
files="$(grep -rIl \
    --exclude-dir=.git --exclude-dir=node_modules --exclude-dir=.venv --exclude-dir=dist \
    --exclude-dir=__pycache__ --exclude-dir=.ruff_cache --exclude-dir=.pytest_cache \
    --exclude=.env --exclude="$(basename "$0")" \
    -e "$T_OWNER_REPO" -e "$T_SLUG" -e "$T_SNAKE" -e "$T_PASCAL" -e "$T_TITLE" . || true)"

# Files that carry the template's port as a standalone number (config, compose defaults,
# the Vite proxy target, docs). Lockfiles are skipped: a hex hash may contain "8050".
# grep -F shortlists, perl decides with word boundaries (portable: no ERE anchors in groups).
port_files=""
if [ "$port" != "$T_PORT" ]; then
    port_files="$(grep -rIlF \
        --exclude-dir=.git --exclude-dir=node_modules --exclude-dir=.venv --exclude-dir=dist \
        --exclude-dir=__pycache__ --exclude-dir=.ruff_cache --exclude-dir=.pytest_cache \
        --exclude=.env --exclude=package-lock.json --exclude=uv.lock --exclude="$(basename "$0")" \
        -- "$T_PORT" . 2>/dev/null \
        | xargs perl -lne "if (/(?<![0-9A-Za-z])${T_PORT}(?![0-9A-Za-z])/) { print \$ARGV; close ARGV }" 2>/dev/null \
        || true)"
fi

if [ -z "$files" ] && [ -z "$port_files" ]; then
    echo "Nothing to rename (already done?)."
    exit 0
fi

if [ -n "$files" ]; then
    # Brace delimiters: the owner/repo pattern contains a slash. \Q..\E quotes regex metachars.
    # shellcheck disable=SC2086
    perl -pi -e "s{\Q$T_OWNER_REPO\E}{$owner/$slug}g; s{\Q$T_SLUG\E}{$slug}g; s{\Q$T_SNAKE\E}{$snake}g; s{\Q$T_PASCAL\E}{$pascal}g; s{\Q$T_TITLE\E}{$title}g" $files
fi
if [ -n "$port_files" ]; then
    # Only a standalone 8050 (not part of a longer number, a word or a hash) becomes the port.
    # shellcheck disable=SC2086
    perl -pi -e "s{(?<![0-9A-Za-z])${T_PORT}(?![0-9A-Za-z])}{$port}g" $port_files
fi

echo "Rewrote:"
printf '  %s\n' $files $port_files | sort -u
echo
if [ -f .env ]; then
    echo "NOTE: an existing .env was left untouched — update PROJECT_NAME/APP_PORT/POSTGRES_*/MINIO_* there by hand,"
    echo "      or delete it and run 'make init' again."
fi
echo "Next:"
echo "  git diff                      # review"
echo "  git commit -am \"[INIT] start $slug from project-template\""
echo "  make init                     # .env + secrets, MinIO bucket, dev stack, migrations, npm ci"
echo "Then work through docs/adapting.md for the remaining (non-mechanical) decisions."
