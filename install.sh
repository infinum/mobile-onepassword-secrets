#!/usr/bin/env bash
# install.sh — Install app-secrets to a writable directory on PATH.
# Usage:  bash install.sh [--silent]
# --silent skips the confirmation prompt (used by --update).

set -euo pipefail

REPO_URL="https://github.com/infinum/mobile-onepassword-secrets.git"
BIN_NAME="app-secrets"
SOURCES_NAME=".app-secrets-sources"

SILENT=false
[[ "${1:-}" == "--silent" ]] && SILENT=true

# Pick an install dir that is writable and on PATH.
choose_bindir() {
    local candidates=("/usr/local/bin" "$HOME/.local/bin")
    local dir
    for dir in "${candidates[@]}"; do
        if [[ -d "$dir" && -w "$dir" ]]; then
            echo "$dir"; return 0
        fi
    done
    # /usr/local/bin exists but not writable → signal sudo path.
    if [[ -d "/usr/local/bin" ]]; then
        echo "/usr/local/bin"; return 2
    fi
    mkdir -p "$HOME/.local/bin"
    echo "$HOME/.local/bin"; return 0
}

main() {
    local bindir rc use_sudo="" tmp
    bindir=$(choose_bindir) || rc=$?
    rc=${rc:-0}
    if [[ "$rc" -eq 2 ]]; then
        echo "Note: $bindir is not writable; will use sudo."
        use_sudo="sudo"
    fi

    if [[ "$SILENT" != true ]]; then
        echo "This will install '$BIN_NAME' to $bindir."
        read -r -p "Do you want to proceed? [y/n] " answer
        [[ "$answer" == "y" ]] || { echo "Aborted."; exit 0; }
    fi

    tmp="$(mktemp -d)"
    trap 'rm -rf "$tmp"' EXIT
    git clone --quiet "$REPO_URL" "$tmp"

    # Announce before overwriting an existing install.
    if [[ -e "$bindir/$BIN_NAME" || -e "$bindir/$SOURCES_NAME" ]]; then
        echo "Replacing existing install at $bindir."
    fi

    # SC2086: $use_sudo is intentionally unquoted so that when empty it
    # expands to nothing (no sudo), and when set to "sudo" it becomes a
    # single word prefix. Quoting it would break the empty case.
    # shellcheck disable=SC2086
    $use_sudo cp "$tmp/$BIN_NAME.sh" "$bindir/$BIN_NAME"
    # shellcheck disable=SC2086
    $use_sudo chmod +rx "$bindir/$BIN_NAME"

    # shellcheck disable=SC2086
    $use_sudo rm -rf "$bindir/$SOURCES_NAME"
    # shellcheck disable=SC2086
    $use_sudo mkdir -p "$bindir/$SOURCES_NAME"
    # shellcheck disable=SC2086
    $use_sudo cp -a "$tmp/sources/." "$bindir/$SOURCES_NAME/"
    # shellcheck disable=SC2086
    $use_sudo chmod -R +rx "$bindir/$SOURCES_NAME"

    # The installed entry must default to the installed sources dir.
    # shellcheck disable=SC2086
    $use_sudo sed -i.bak "s|/usr/local/bin/.app-secrets-sources|$bindir/$SOURCES_NAME|g" "$bindir/$BIN_NAME"
    # shellcheck disable=SC2086
    $use_sudo rm -f "$bindir/$BIN_NAME.bak"

    echo
    echo "Installed: $bindir/$BIN_NAME"
    echo "Run '$BIN_NAME --help' to get started."
}

main "$@"
