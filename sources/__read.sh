#!/usr/bin/env bash
# __read — downloads secret files from 1Password into the local path.
# shellcheck disable=SC2154
# SC2154: path, vaults, CLI_NAME are runtime-injected globals
# (loaded by load_config or set in tests/entry point).

__read_usage() {
    echo "Usage: $CLI_NAME read [-h] [vault]"
    echo
    echo "Downloads secret files from 1Password into the local path."
    echo "For each configured vault, lists its documents and downloads the ones"
    echo "whose name matches that vault's patterns, preserving relative paths."
    echo
    echo "Arguments:"
    echo "  vault   Optional. Restrict the download to a single vault."
    echo
    echo "Options:"
    echo "  -h      Show this help message and exit."
    return 0
}

# Resolves a CLI vault arg to a configured vault name (case-insensitive).
resolve_vault_filter() {
    local arg="$1"
    local arg_lc vault vault_lc
    arg_lc=$(to_lower "$arg")
    for vault in "${vaults[@]+"${vaults[@]}"}"; do
        vault_lc=$(to_lower "$vault")
        if [[ "$vault_lc" == "$arg_lc" ]]; then
            echo "$vault"
            return 0
        fi
    done
    return 1
}

# Lists documents in a vault and downloads those matching the vault's patterns.
# The document title is treated as the file's path relative to $path.
__read_pull_vault() {
    local vault="$1"
    local title dir

    while IFS= read -r title; do
        [[ -n "$title" ]] || continue
        vault_matches_file "$vault" "$title" || continue

        dir=$(dirname "$title")
        mkdir -p "$path/$dir"
        op document get "$title" --vault "$vault" --out-file "$path/$title" --force
        echo "[+] $title (from $vault)"
    done < <(op document list --vault "$vault" --format=json 2>/dev/null | jq -r '.[].title')
    return 0
}

__read() {
    local arg="${1:-}"
    if [[ "$arg" == "-h" || "$arg" == "--help" ]]; then
        __read_usage; return 0
    fi

    require_tools || exit 1
    setup_styles
    load_config || exit 1
    platform_validate "$platform" || exit 1

    mkdir -p "$path"

    local vault_filter=""
    if [[ -n "$arg" ]]; then
        if ! vault_filter=$(resolve_vault_filter "$arg"); then
            echo "Invalid vault argument: $arg"
            echo "Available: ${vaults[*]+"${vaults[*]}"}"
            echo
            __read_usage
            exit 1
        fi
        echo "Filtering to vault: $vault_filter"
        echo
    fi

    detect_vault_access can_access_vault "read" "$vault_filter"
    echo

    echo "Fetching configurations..."
    echo

    local vault
    for vault in "${vaults[@]+"${vaults[@]}"}"; do
        if [[ -n "$vault_filter" && "$vault" != "$vault_filter" ]]; then
            continue
        fi
        if ! can_access_vault "$vault"; then
            echo "[!] No access to '$vault', skipping"
            continue
        fi
        __read_pull_vault "$vault"
    done

    echo
    echo "Done!"
    return 0
}
