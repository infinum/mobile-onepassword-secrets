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

    # Establish the op session up front (may prompt via the 1Password app;
    # OP_SERVICE_ACCOUNT_TOKEN answers instantly on CI). Doing it before the
    # access checks keeps a pending sign-in from reading as "no vault access".
    ensure_op_session || exit 1

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

    # Warm the per-vault item cache in this shell: resolution below runs in
    # command substitutions (subshells), which inherit but can't fill it.
    for vault in "${needed[@]}"; do
        get_vault_items "$vault" > /dev/null
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

    # Resolve each file to its item (title + 'path' field), then edit by id or
    # create-and-stamp. claimed ids stop two same-named entries from adopting
    # the same unstamped item.
    local file verdict action id out new_id claimed=""
    for i in "${!up_files[@]}"; do
        file="${up_files[$i]}"
        vault="${up_vaults[$i]}"
        title=$(doc_title_for "$file")
        verdict=$(resolve_item_for_path "$vault" "$file" "$claimed")
        action="${verdict%% *}"
        id="${verdict#* }"

        case "$action" in
            found|adopt)
                if ! op document edit "$id" "$file" --vault "$vault"; then
                    echo "[!] Could not upload $file to '$vault'"
                    continue
                fi
                if [[ "$action" == "adopt" ]]; then
                    stamp_item_path "$id" "$file" "$vault" \
                        || echo "[!] Uploaded, but could not set 'path' on document '$title' in '$vault'"
                fi
                claimed="${claimed:+$claimed,}$id"
                echo "[+] $file → $vault (document '$title')"
                ;;
            none)
                if ! out=$(op document create "$file" --title "$title" --vault "$vault" --format json); then
                    echo "[!] Could not upload $file to '$vault'"
                    continue
                fi
                new_id=$(printf '%s' "$out" | jq -r '.id // .uuid // empty' 2>/dev/null) || new_id=""
                if [[ -n "$new_id" ]]; then
                    stamp_item_path "$new_id" "$file" "$vault" \
                        || echo "[!] Uploaded, but could not set 'path' on document '$title' in '$vault'"
                    claimed="${claimed:+$claimed,}$new_id"
                else
                    echo "[!] Uploaded, but could not read the new item id to set 'path' (the next write adopts and stamps it)"
                fi
                echo "[+] $file → $vault (document '$title')"
                ;;
            ambiguous)
                echo "[!] Multiple documents titled '$title' in '$vault' and none matches path '$file' — skipping. Set the 'path' text field on the right item or remove duplicates."
                ;;
        esac
    done

    echo
    echo "Done!"
    return 0
}
