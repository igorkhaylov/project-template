#!/bin/sh
# Runs before the nginx entrypoint renders default.conf.template. The APP_* values are
# pasted into a JavaScript string literal in /config.js, so a double quote, backslash
# or control character would break every page load. Fail fast at container start
# instead, with the offending variable named.
set -e
# Command substitution strips trailing newlines, hence the sentinel character.
nl=$(printf '\nx'); nl=${nl%x}
cr=$(printf '\rx'); cr=${cr%x}
for var in APP_API_BASE_URL APP_ENVIRONMENT; do
    eval "value=\${$var:-}"
    case "$value" in
        *'"'*|*'\'*|*"$nl"*|*"$cr"*)
            echo "ERROR: $var contains a quote, backslash or newline and cannot be rendered into /config.js" >&2
            exit 1 ;;
    esac
done
case "${APP_API_BASE_URL:-}" in
    ""|http://*|https://*) ;;
    *) echo "ERROR: APP_API_BASE_URL must be empty (same origin) or start with http:// or https://" >&2; exit 1 ;;
esac
