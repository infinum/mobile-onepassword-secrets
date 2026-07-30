#!/usr/bin/env bash
# __read — downloads secret files from 1Password to their configured paths.
# shellcheck disable=SC2154
# SC2154: vaults, file_vaults, vault_aliases, CLI_NAME are runtime-injected
# globals (loaded by load_config or set in tests/entry point).

__read_usage() {
    echo "Usage: $CLI_NAME read [-h] [vault]"
    echo
    echo "Downloads each configured file from its 1Password vault to the file's"
    echo "path (the document title is the file name). Creates folders as needed."
    echo
    echo "Arguments:"
    echo "  vault   Optional. Restrict to one vault (its name or friendly label)."
    echo
    echo "Options:"
    echo "  -h      Show this help message and exit."
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

    # No sign-in precheck: op prompts for sign-in on its first call (via the
    # 1Password app integration), or uses OP_SERVICE_ACCOUNT_TOKEN on CI.

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

    local entry rel vault title dir
    for entry in "${file_vaults[@]+"${file_vaults[@]}"}"; do
        rel="${entry%:*}"
        vault="${entry##*:}"

        if [[ -n "$vault_filter" && "$vault" != "$vault_filter" ]]; then
            continue
        fi
        if ! can_access_vault "$vault"; then
            echo "[!] No access to '$vault', skipping $rel"
            continue
        fi

        title=$(doc_title_for "$rel")
        dir=$(dirname "$rel")
        mkdir -p "$dir"

        if op document get "$title" --vault "$vault" --out-file "$rel" --force; then
            echo "[+] $rel (from $vault, document '$title')"
        else
            echo "[!] Could not fetch document '$title' from '$vault' for $rel"
        fi
    done

    echo
    echo "Done!"
    return 0
}
