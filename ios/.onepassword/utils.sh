#!/usr/bin/env bash

# utils.sh - Helper functions for 1password scripts

# Load shared configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/config.sh"

# Required tooling
if ! command -v op >/dev/null 2>&1; then
    echo "Error: 1Password CLI 'op' is required but not installed." >&2
    echo "Install with: brew install --cask 1password-cli" >&2
    exit 1
fi
if ! command -v jq >/dev/null 2>&1; then
    echo "Error: 'jq' is required but not installed." >&2
    echo "Install with: brew install jq" >&2
    exit 1
fi

# Colors / styles (gracefully degrade when no terminal is available, e.g. CI).
# Consumed by sourcing scripts.
# shellcheck disable=SC2034
{
    green=$(tput setaf 2 2>/dev/null || true)
    red=$(tput setaf 1 2>/dev/null || true)
    bold=$(tput bold 2>/dev/null || true)
    reset=$(tput sgr0 2>/dev/null || true)
    normal="$reset"
}

# Lowercase a string portably (bash 3.2 has no ${var,,}).
to_lower() {
    printf '%s' "$1" | tr '[:upper:]' '[:lower:]'
}

# Returns the mapped vault for a filename by matching against file_vaults entries.
# Each entry is "glob_pattern:vault". First match wins.
get_vault_for_file() {
    local file_name="$1"
    local entry pattern vault
    for entry in "${file_vaults[@]}"; do
        pattern="${entry%:*}"
        vault="${entry##*:}"
        # shellcheck disable=SC2053
        if [[ "$file_name" == $pattern ]]; then
            echo "$vault"
            return 0
        fi
    done
    return 1
}

# Vault access detection (cached)
_accessible_vaults=""
_current_user_id=""

# Returns a newline-separated list of vault names the current user can see; result is cached.
get_accessible_vaults() {
    if [[ -z "$_accessible_vaults" ]]; then
        _accessible_vaults=$(op vault list --format=json 2>/dev/null | jq -r '.[].name')
    fi
    echo "$_accessible_vaults"
    return 0
}

# Returns the current 1Password user ID; result is cached.
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

# Returns 0 if the current user has write (allow_editing) permission on the given vault.
can_write_vault() {
    local vault_name="$1"

    local user_id
    user_id=$(_get_current_user_id)
    if [[ -z "$user_id" ]]; then
        return 1
    fi

    op vault user list "$vault_name" --format=json 2>/dev/null \
        | jq -e --arg uid "$user_id" '.[] | select(.id == $uid) | .permissions | index("allow_editing")' \
        > /dev/null 2>&1
}

# Prints each vault with a green checkmark or red cross based on the given access-check function.
print_vault_access() {
    local check_fn="$1"  # can_access_vault or can_write_vault
    for vault in "${vaults[@]}"; do
        if $check_fn "$vault"; then
            echo "  ${green}✓${reset} $vault"
        else
            echo "  ${red}✗${reset} $vault"
        fi
    done
    return 0
}

# Detects vault access, prints status, and exits if none accessible.
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

        local any_accessible=false
        for vault in "${vaults[@]}"; do
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
