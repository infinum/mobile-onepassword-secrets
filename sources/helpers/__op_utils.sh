#!/usr/bin/env bash
# sources/helpers/__op_utils.sh
# shellcheck disable=SC2034,SC2154
# SC2034: color/cache vars set here are consumed by sourcing scripts.
# SC2154: file_vaults and vaults are injected at runtime by the config parser or tests.
# Helper functions for 1Password interaction. Sourcing is side-effect-free;
# call require_tools / setup_styles explicitly.

# Verifies required CLIs are installed. Call before any op-dependent command.
require_tools() {
    if ! command -v op >/dev/null 2>&1; then
        echo "Error: 1Password CLI 'op' is required but not installed." >&2
        echo "Install with: brew install --cask 1password-cli" >&2
        return 1
    fi
    if ! command -v jq >/dev/null 2>&1; then
        echo "Error: 'jq' is required but not installed." >&2
        echo "Install with: brew install jq" >&2
        return 1
    fi
    return 0
}

# Runs a command with a hard timeout, killing it (SIGKILL) if it overruns.
# stdin is taken from /dev/null so a hidden prompt can't block. Output discarded.
# `op` ignores soft signals while waiting on the desktop-app integration, so we
# poll and SIGKILL — a soft timeout is not enough.
# Usage: op_bounded <seconds> <command> [args...]  → command status, or 124 on timeout.
op_bounded() {
    local secs="$1"; shift
    local pid waited=0 rc=0
    "$@" </dev/null >/dev/null 2>&1 &
    pid=$!
    while kill -0 "$pid" 2>/dev/null; do
        if [[ "$waited" -ge "$secs" ]]; then
            kill -9 "$pid" 2>/dev/null
            wait "$pid" 2>/dev/null || true
            return 124
        fi
        sleep 1
        waited=$((waited + 1))
    done
    if wait "$pid"; then rc=0; else rc=$?; fi
    return "$rc"
}

# Returns 0 if there is a usable 1Password session (bounded, non-interactive).
# `op whoami` works for both personal sign-ins and service-account tokens
# (unlike `op user get --me`, which fails for service accounts).
# Returns 124 if op did not respond in time, or op's error status otherwise.
op_signed_in() {
    op_bounded "${1:-10}" op whoami
}

# True if a 1Password service-account token is configured. `op` uses it
# automatically (CI-friendly, no desktop app). Service accounts have no user
# identity, so user-based permission checks don't apply to them.
is_service_account() {
    [[ -n "${OP_SERVICE_ACCOUNT_TOKEN:-}" ]]
}

# Colors / styles. Gracefully degrade with no terminal (e.g. CI).
# shellcheck disable=SC2034
setup_styles() {
    green=$(tput setaf 2 2>/dev/null || true)
    red=$(tput setaf 1 2>/dev/null || true)
    bold=$(tput bold 2>/dev/null || true)
    reset=$(tput sgr0 2>/dev/null || true)
}

# Lowercase a string portably (bash 3.2 has no ${var,,}).
to_lower() {
    printf '%s' "$1" | tr '[:upper:]' '[:lower:]'
}

# The 1Password document title for a file path: its base name (with extension).
# e.g. Keys/Keys.staging.swift -> Keys.staging.swift
doc_title_for() {
    echo "${1##*/}"
}

# Resolves a CLI arg (a vault name or friendly label) to the 1Password vault
# name, using the vault_aliases map. Case-insensitive.
resolve_vault_filter() {
    local arg_lc key vault entry
    arg_lc=$(to_lower "$1")
    for entry in "${vault_aliases[@]+"${vault_aliases[@]}"}"; do
        key="${entry%:*}"
        vault="${entry##*:}"
        if [[ "$(to_lower "$key")" == "$arg_lc" ]]; then
            echo "$vault"
            return 0
        fi
    done
    return 1
}

_accessible_vaults=""
_current_user_id=""

# Newline-separated list of vault names the current user can see; cached.
get_accessible_vaults() {
    if [[ -z "$_accessible_vaults" ]]; then
        _accessible_vaults=$(op vault list --format=json 2>/dev/null | jq -r '.[].name')
    fi
    echo "$_accessible_vaults"
    return 0
}

# Current 1Password user ID; cached.
_get_current_user_id() {
    if [[ -z "$_current_user_id" ]]; then
        _current_user_id=$(op user get --me --format=json 2>/dev/null | jq -r '.id')
    fi
    echo "$_current_user_id"
    return 0
}

# Returns 0 if the current user has read access to the given vault.
can_access_vault() {
    local vault_name="$1"
    get_accessible_vaults | grep -qx "$vault_name"
    return $?
}

# Returns 0 if the current user has write (allow_editing) permission on the vault.
can_write_vault() {
    local vault_name="$1"
    # Service accounts have no user identity to introspect; assume writable and
    # let `op` enforce on the actual write (they are read-only unless granted).
    if is_service_account; then
        return 0
    fi
    local user_id
    user_id=$(_get_current_user_id)
    if [[ -z "$user_id" ]]; then
        return 1
    fi
    op vault user list "$vault_name" --format=json 2>/dev/null \
        | jq -e --arg uid "$user_id" '.[] | select(.id == $uid) | .permissions | index("allow_editing")' \
        > /dev/null 2>&1
}

# Prints each vault with a green check or red cross per the given check function.
print_vault_access() {
    local check_fn="$1"  # can_access_vault or can_write_vault
    local vault
    for vault in "${vaults[@]+"${vaults[@]}"}"; do
        if $check_fn "$vault"; then
            echo "  ${green}✓${reset} $vault"
        else
            echo "  ${red}✗${reset} $vault"
        fi
    done
    return 0
}

# Detects vault access, prints status, exits if none accessible.
# Usage: detect_vault_access <check_fn> [label] [vault_filter]
detect_vault_access() {
    local check_fn="$1"
    local label="${2:-}"
    local vault_filter="${3:-}"

    echo "Detecting vault ${label} access..."
    if [[ -n "$vault_filter" ]]; then
        if ! $check_fn "$vault_filter"; then
            echo "  ${red}✗${reset} $vault_filter"
            echo
            echo "You don't have ${label} access to vault '$vault_filter'. Please check your access with the team."
            exit 1
        fi
        echo "  ${green}✓${reset} $vault_filter"
    else
        print_vault_access "$check_fn"
        local any_accessible=false vault
        for vault in "${vaults[@]+"${vaults[@]}"}"; do
            $check_fn "$vault" && { any_accessible=true; break; }
        done
        if [[ "$any_accessible" = false ]]; then
            echo
            echo "You don't have ${label} access to any vault. Please check your access with the team."
            exit 1
        fi
    fi
    return 0
}
