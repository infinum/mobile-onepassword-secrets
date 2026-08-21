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

# Queues one file for upload, ignoring a file:vault pair that is already
# queued — a duplicated config entry would otherwise create a second item
# stamped with the same path. Also records the vault the first time it is
# seen, so its access check and item list happen once per run.
#
# Operates on __write's upload_paths / upload_vaults / target_vaults arrays
# (bash scoping makes the caller's locals visible here).
queue_upload() {
    local rel_path="$1" vault="$2" i queued
    for i in ${upload_paths[@]+"${!upload_paths[@]}"}; do
        if [[ "${upload_paths[$i]}" == "$rel_path" && "${upload_vaults[$i]}" == "$vault" ]]; then
            return 0
        fi
    done
    upload_paths+=("$rel_path")
    upload_vaults+=("$vault")
    for queued in "${target_vaults[@]+"${target_vaults[@]}"}"; do
        if [[ "$queued" == "$vault" ]]; then
            return 0
        fi
    done
    target_vaults+=("$vault")
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
    local -a upload_paths=() upload_vaults=() target_vaults=()
    local entry rel_path vault
    for entry in "${file_vaults[@]+"${file_vaults[@]}"}"; do
        rel_path="${entry%:*}"
        vault="${entry##*:}"
        [[ -n "$vault_filter" && "$vault" != "$vault_filter" ]] && continue

        if [[ ! -f "$rel_path" ]]; then
            echo "[!] Local file missing, skipping: $rel_path"
            continue
        fi
        queue_upload "$rel_path" "$vault"
    done

    # Expand glob/folder patterns against the local tree; matches join the
    # upload list unless an explicit entry already claimed them.
    local pattern matches match
    for entry in "${pattern_vaults[@]+"${pattern_vaults[@]}"}"; do
        pattern="${entry%:*}"
        vault="${entry##*:}"
        [[ -n "$vault_filter" && "$vault" != "$vault_filter" ]] && continue

        matches=$(expand_glob_local "$pattern")
        if [[ -z "$matches" ]]; then
            echo "[!] Pattern matched no local files: $pattern"
            continue
        fi
        while IFS= read -r match; do
            if ! is_safe_rel_path "$match"; then
                echo "[!] Skipping unsafe local match for pattern $pattern: $match"
                continue
            fi
            queue_upload "$match" "$vault"
        done <<< "$matches"
    done

    if [[ "${#upload_paths[@]}" -eq 0 ]]; then
        echo "No local files to upload."
        exit 1
    fi

    # Write-access check for the vaults actually needed.
    for vault in "${target_vaults[@]+"${target_vaults[@]}"}"; do
        detect_vault_access can_write_vault "write" "$vault"
    done

    # Warm the per-vault item cache in this shell: resolution below runs in
    # command substitutions (subshells), which inherit but can't fill it.
    for vault in "${target_vaults[@]+"${target_vaults[@]}"}"; do
        get_vault_items "$vault" > /dev/null
    done

    # Preview.
    echo
    echo "The following will be uploaded:"
    local i title
    for i in "${!upload_paths[@]}"; do
        title=$(doc_title_for "${upload_paths[$i]}")
        echo "  [+] ${upload_paths[$i]} → ${upload_vaults[$i]} (document '$title')"
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
    for i in "${!upload_paths[@]}"; do
        file="${upload_paths[$i]}"
        vault="${upload_vaults[$i]}"
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
                if ! op document edit "$id" "$file" --vault "$vault" >/dev/null; then
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

    # Moving a file leaves the old item behind: write creates a fresh one at
    # the new path while the old keeps its stamp, so a folder pattern would
    # keep restoring the file at its old location on every read. Point at the
    # leftover — deleting items in 1Password is the user's call, not ours.
    # Paths listed literally in the config are left alone: their absence is
    # already reported above as a missing local file.
    local stale_title stale_path idx literal items
    for vault in "${target_vaults[@]+"${target_vaults[@]}"}"; do
        items=$(get_vault_items "$vault")
        [[ "$items" == "FAILED" ]] && continue
        while IFS=$'\t' read -r stale_title stale_path; do
            [[ -n "$stale_path" ]] || continue
            [[ -e "$stale_path" ]] && continue
            literal=false
            for e in "${file_vaults[@]+"${file_vaults[@]}"}"; do
                [[ "$e" == "$stale_path:$vault" ]] && { literal=true; break; }
            done
            [[ "$literal" == true ]] && continue
            for idx in "${!upload_paths[@]}"; do
                [[ "${upload_vaults[$idx]}" == "$vault" ]] || continue
                [[ "${upload_paths[$idx]}" != "$stale_path" ]] || continue
                [[ "$(doc_title_for "${upload_paths[$idx]}")" == "$stale_title" ]] || continue
                echo "[!] '$vault' still has a document stamped '$stale_path', but there is no local file there — ${upload_paths[$idx]} looks like where it moved. Delete the old item in 1Password, or read will keep restoring it."
                break
            done
        done < <(printf '%s' "$items" | jq -r '.[] | . as $it | (.fields // [])[]
            | select(.label == "path") | [$it.title, .value] | @tsv')
    done

    echo
    if [[ "$failed" -ne 0 ]]; then
        echo "Done, with errors — some files were not uploaded."
        return 1
    fi
    echo "Done!"
    return 0
}
