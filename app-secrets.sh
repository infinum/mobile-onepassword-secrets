#!/usr/bin/env bash

set -euo pipefail

# Resolve library dir. APP_SECRETS_SOURCES wins when set (Homebrew's env
# wrapper, dev, tests). Otherwise use the sources/ directory next to this
# script - following symlinks first, since npm installs the command as a
# symlink into its bin directory.
if [[ -z "${APP_SECRETS_SOURCES:-}" ]]; then
    _self="${BASH_SOURCE[0]}"
    while [[ -L "$_self" ]]; do
        _dir="$(cd "$(dirname "$_self")" && pwd)"
        _self="$(readlink "$_self")"
        [[ "$_self" == /* ]] || _self="$_dir/$_self"
    done
    APP_SECRETS_SOURCES="$(cd "$(dirname "$_self")" && pwd)/sources"
    unset _self _dir
fi
SOURCES_DIR="$APP_SECRETS_SOURCES"

if [[ ! -d "$SOURCES_DIR" ]]; then
    echo "Error: sources directory not found at $SOURCES_DIR" >&2
    echo "Reinstall app-secrets (brew install infinum/tap/app-secrets, or" >&2
    echo "npm install -g @infinum/app-secrets), or point APP_SECRETS_SOURCES" >&2
    echo "at a checkout's sources/ directory." >&2
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
