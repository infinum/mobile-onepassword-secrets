#!/usr/bin/env bash

set -euo pipefail

# Resolve library dir. Installed default; override for dev/tests.
SOURCES_DIR="${INFINUM_SECRETS_SOURCES:-/usr/local/bin/.infinum-secrets-sources}"

if [[ ! -d "$SOURCES_DIR" ]]; then
    echo "Error: sources directory not found at $SOURCES_DIR" >&2
    echo "Reinstall infinum-secrets, or set INFINUM_SECRETS_SOURCES." >&2
    exit 1
fi

# Source helpers first, then top-level command files. Guard empty globs.
for _f in "$SOURCES_DIR"/helpers/*.sh "$SOURCES_DIR"/*.sh; do
    [[ -e "$_f" ]] || continue
    # shellcheck disable=SC1090
    source "$_f"
done

case "${1:-}" in
    -h|--help|help)
        __help
        ;;
    -v|--version)
        echo "$CLI_NAME $VERSION"
        ;;
    --update)
        __script_auto_update
        ;;
    init)
        shift
        __init "$@"
        ;;
    read)
        shift
        __read "$@"
        ;;
    write)
        shift
        __write "$@"
        ;;
    doctor|status)
        shift
        __doctor "$@"
        ;;
    "")
        echo "No command given. Try '$CLI_NAME --help'." >&2
        exit 1
        ;;
    *)
        echo "Unsupported command: $1" >&2
        echo "Try '$CLI_NAME --help'." >&2
        exit 1
        ;;
esac
