#!/usr/bin/env bash
# __write — uploads configured secret files to their 1Password vaults.
# shellcheck disable=SC2154
# SC2154: vaults, file_vaults, vault_aliases, CLI_NAME, green/red/reset are
# runtime-injected globals (loaded by load_config / setup_styles / entry / tests).

__write_usage() {
    echo "Usage: $CLI_NAME write [-h] [vault]"
    echo
    echo "Uploads each configured local file to its 1Password vault (the document"
    echo "title is the file name). Files listed in config but missing locally are"
    echo "skipped."
    echo
    echo "Arguments:"
    echo "  vault   Optional. Restrict to one vault (its name or friendly label)."
    echo
    echo "Options:"
    echo "  -h      Show this help message and exit."
    return 0
}

__write() {
    local arg="${1:-}"
    if [[ "$arg" == "-h" || "$arg" == "--help" ]]; then
        __write_usage; return 0
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
            __write_usage
            exit 1
        fi
    fi

    # Collect files that exist locally (and match the optional vault filter).
    local -a up_files=() up_vaults=() needed=()
    local entry rel vault existing e
    for entry in "${file_vaults[@]+"${file_vaults[@]}"}"; do
        rel="${entry%:*}"
        vault="${entry##*:}"
        [[ -n "$vault_filter" && "$vault" != "$vault_filter" ]] && continue

        if [[ ! -f "$rel" ]]; then
            echo "[!] Local file missing, skipping: $rel"
            continue
        fi
        up_files+=("$rel")
        up_vaults+=("$vault")
        existing=false
        for e in "${needed[@]+"${needed[@]}"}"; do
            [[ "$e" == "$vault" ]] && { existing=true; break; }
        done
        [[ "$existing" = false ]] && needed+=("$vault")
    done

    if [[ "${#up_files[@]}" -eq 0 ]]; then
        echo "No local files to upload."
        exit 1
    fi

    # Write-access check for the vaults actually needed.
    for vault in "${needed[@]}"; do
        detect_vault_access can_write_vault "write" "$vault"
    done

    # Preview.
    echo
    echo "The following will be uploaded:"
    local i title
    for i in "${!up_files[@]}"; do
        title=$(doc_title_for "${up_files[$i]}")
        echo "  [+] ${up_files[$i]} → ${up_vaults[$i]} (document '$title')"
    done

    # Confirm only when interactive; automation (CI) proceeds.
    if [[ -t 0 ]]; then
        echo
        local response
        read -r -e -p "Upload these? Press enter to continue, or 'q' to quit: " response
        [[ $response == q ]] && { echo "Aborted."; exit 0; }
    fi

    echo
    echo "Uploading..."
    echo

    local file
    for i in "${!up_files[@]}"; do
        file="${up_files[$i]}"
        vault="${up_vaults[$i]}"
        title=$(doc_title_for "$file")
        if op item get "$title" --vault "$vault" > /dev/null 2>&1; then
            op document edit "$title" "$file" --vault "$vault"
        else
            op document create "$file" --title "$title" --vault "$vault"
        fi
        echo "[+] $file → $vault (document '$title')"
    done

    echo
    echo "Done!"
    return 0
}
