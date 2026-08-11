#!/usr/bin/env bash
# __write — uploads configured secret files to their 1Password vaults.
# shellcheck disable=SC2154
# SC2154: vaults, file_vaults, vault_aliases, CLI_NAME, green/red/reset are
# runtime-injected globals (loaded by load_config / setup_styles / entry / tests).

__write_usage() {
    echo "Usage: $CLI_NAME write [-h] [vault]"
    echo
    echo "Uploads each configured local file to its 1Password vault (the document"
    echo "title is the file name; the repo-relative path is stamped on the item"
    echo "as a 'path' field). Pattern entries (globs, folder shorthand) expand"
    echo "against the local tree. Files listed in config but missing locally are"
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
    # Dedupe repeats of the same file:vault pair — a duplicated entry would
    # otherwise create a second item stamped with the same path.
    local -a up_files=() up_vaults=() needed=()
    local entry rel vault existing e dup j
    for entry in "${file_vaults[@]+"${file_vaults[@]}"}"; do
        rel="${entry%:*}"
        vault="${entry##*:}"
        [[ -n "$vault_filter" && "$vault" != "$vault_filter" ]] && continue

        if [[ ! -f "$rel" ]]; then
            echo "[!] Local file missing, skipping: $rel"
            continue
        fi
        dup=false
        for j in ${up_files[@]+"${!up_files[@]}"}; do
            if [[ "${up_files[$j]}" == "$rel" && "${up_vaults[$j]}" == "$vault" ]]; then
                dup=true
                break
            fi
        done
        [[ "$dup" == true ]] && continue
        up_files+=("$rel")
        up_vaults+=("$vault")
        existing=false
        for e in "${needed[@]+"${needed[@]}"}"; do
            [[ "$e" == "$vault" ]] && { existing=true; break; }
        done
        [[ "$existing" = false ]] && needed+=("$vault")
    done

    # Expand glob/folder patterns against the local tree; matches join the
    # upload list unless an explicit entry already claimed them.
    local pat matches m dup j
    for entry in "${pattern_vaults[@]+"${pattern_vaults[@]}"}"; do
        pat="${entry%:*}"
        vault="${entry##*:}"
        [[ -n "$vault_filter" && "$vault" != "$vault_filter" ]] && continue

        matches=$(expand_glob_local "$pat")
        if [[ -z "$matches" ]]; then
            echo "[!] Pattern matched no local files: $pat"
            continue
        fi
        while IFS= read -r m; do
            if ! is_safe_rel_path "$m"; then
                echo "[!] Skipping unsafe local match for pattern $pat: $m"
                continue
            fi
            dup=false
            for j in ${up_files[@]+"${!up_files[@]}"}; do
                if [[ "${up_files[$j]}" == "$m" && "${up_vaults[$j]}" == "$vault" ]]; then
                    dup=true
                    break
                fi
            done
            [[ "$dup" == true ]] && continue
            up_files+=("$m")
            up_vaults+=("$vault")
            existing=false
            for e in "${needed[@]+"${needed[@]}"}"; do
                [[ "$e" == "$vault" ]] && { existing=true; break; }
            done
            [[ "$existing" = false ]] && needed+=("$vault")
        done <<< "$matches"
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
    # Anything that leaves a collected file unpublished (or an item in an
    # inconsistent state) flips this; the run ends non-zero so CI cannot
    # mistake "uploaded nothing" for "uploaded everything".
    local failed=0
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
                # Claim on resolution, not on success: a failed upload must not
                # release the id, or the next file sharing this base name would
                # adopt the same item and overwrite it with the wrong secret.
                claimed="${claimed:+$claimed,}$id"
                if ! op document edit "$id" "$file" --vault "$vault"; then
                    echo "[!] Could not upload $file to '$vault'"
                    failed=1
                    continue
                fi
                if [[ "$action" == "adopt" ]]; then
                    stamp_item_path "$id" "$file" "$vault" || {
                        echo "[!] Uploaded, but could not set 'path' on document '$title' in '$vault'"
                        failed=1
                    }
                fi
                echo "[+] $file → $vault (document '$title')"
                ;;
            none)
                if ! out=$(op document create "$file" --title "$title" --vault "$vault" --format json); then
                    echo "[!] Could not upload $file to '$vault'"
                    failed=1
                    continue
                fi
                new_id=$(printf '%s' "$out" | jq -r '.id // .uuid // empty' 2>/dev/null) || new_id=""
                if [[ -n "$new_id" ]]; then
                    stamp_item_path "$new_id" "$file" "$vault" || {
                        echo "[!] Uploaded, but could not set 'path' on document '$title' in '$vault'"
                        failed=1
                    }
                    claimed="${claimed:+$claimed,}$new_id"
                else
                    echo "[!] Uploaded, but could not read the new item id to set 'path' (the next write adopts and stamps it)"
                    failed=1
                fi
                echo "[+] $file → $vault (document '$title')"
                ;;
            ambiguous)
                echo "[!] Cannot uniquely resolve document '$title' in '$vault' for path '$file' — skipping. Remove duplicate items in 1Password, or make sure exactly one carries a 'path' field with this value."
                failed=1
                ;;
            error)
                echo "[!] Could not list documents in '$vault', skipping $file"
                failed=1
                ;;
        esac
    done

    echo
    if [[ "$failed" -ne 0 ]]; then
        echo "Done, with errors — some files were not uploaded."
        return 1
    fi
    echo "Done!"
    return 0
}
