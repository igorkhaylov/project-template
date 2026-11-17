#!/usr/bin/env bash
#
# Known-vulnerability audit of the LOCKED dependencies (backend/uv.lock and
# frontend/package-lock.json) against the public advisory databases. Nothing is
# installed and no project code runs: both audits read the lockfile only.
#
#   ops/scripts/audit.sh             # both components
#   ops/scripts/audit.sh backend     # Python: every locked package (runtime, dev group, extras)
#   ops/scripts/audit.sh frontend    # npm: see the two tiers below
#
# The same script is what `make audit` and .github/workflows/audit.yml run, so "audit
# passes" means one thing everywhere. Exit status: 0 = clean, 1 = findings (or a failed
# lookup: an audit that could not run is not a pass).
#
# Why it exists next to Dependabot: update PRs only move packages inside the version
# caps (backend: lockfile-only). A fix that needs a cap raised never arrives as a PR;
# this audit is what turns red in that case.
set -euo pipefail
cd "$(dirname "$0")/../.."

# Advisories accepted for now, by ID (GHSA-…, PYSEC-…, CVE-…). Each is ignored only
# while NO fixed version exists and starts failing again as soon as one is published.
# Accepting a risk is a reviewed code change: add the ID here with a one-line reason.
BACKEND_IGNORE_UNTIL_FIXED=(
)

die() { echo "ERROR: $*" >&2; exit 1; }

audit_backend() {
    command -v docker >/dev/null 2>&1 || die "docker is required for the backend audit"
    # uv comes from the image the backend Dockerfile already pins, so the repository has
    # ONE uv version (Dependabot bumps it there; `uv audit` is still a preview command,
    # and a pinned version keeps its behaviour from changing under us).
    local image id args=()
    image="$(sed -n 's|^COPY --from=\(ghcr\.io/astral-sh/uv:[0-9][0-9.]*\) .*|\1|p' backend/Dockerfile | head -n 1)"
    [ -n "$image" ] || die "could not read the pinned uv image from backend/Dockerfile"
    for id in ${BACKEND_IGNORE_UNTIL_FIXED[@]+"${BACKEND_IGNORE_UNTIL_FIXED[@]}"}; do
        args+=(--ignore-until-fixed "$id")
    done
    echo ">>> backend: uv audit ($image)"
    # The container only has to read uv.lock and reach the advisory service, so it gets
    # nothing else: the caller's uid (not root), a read-only root filesystem and source
    # mount, no capabilities, and a throwaway tmpfs for uv's cache.
    docker run --rm \
        --user "$(id -u):$(id -g)" --read-only --cap-drop ALL --security-opt no-new-privileges \
        --tmpfs /tmp -e HOME=/tmp -e UV_CACHE_DIR=/tmp/uv-cache \
        -v "$PWD/backend:/src:ro" -w /src "$image" \
        audit --frozen --preview-features audit ${args[@]+"${args[@]}"}
}

audit_frontend() {
    command -v npm >/dev/null 2>&1 || die "npm is required for the frontend audit (Node 24+)"
    local status=0
    # Tier 1 — what ships to the browser (dependencies): any advisory fails.
    echo ">>> frontend: npm audit, runtime dependencies (any severity)"
    (cd frontend && npm audit --omit=dev) || status=1
    # Tier 2 — the toolchain (devDependencies: build, lint, test). It never reaches users,
    # but it runs on developer machines and in CI, so high and critical fail; lower
    # severities are listed in the output without failing the audit.
    echo ">>> frontend: npm audit, all dependencies (high and critical)"
    (cd frontend && npm audit --audit-level=high) || status=1
    return "$status"
}

case "${1:-all}" in
    backend)  audit_backend ;;
    frontend) audit_frontend ;;
    all)
        # Run both even when the first fails: one report, not one finding at a time.
        # (Statuses are collected explicitly: `set -e` does not apply inside `||` lists.)
        status=0
        (audit_backend) || status=1
        (audit_frontend) || status=1
        exit "$status" ;;
    -h|--help) sed -n '2,13p' "$0" ;;
    *) echo "Unknown component: $1 (expected: backend, frontend)" >&2; exit 2 ;;
esac
