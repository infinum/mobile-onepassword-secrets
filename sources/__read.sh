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

    # Resolve each file to its item (title + 'path' field) and fetch by id.
    # claimed ids stop two same-named entries from downloading the same
    # unstamped document. Read never stamps — it must work with read-only
    # vault access; write is what stamps.
    local entry rel vault title verdict action id claimed=""
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
        get_vault_items "$vault" > /dev/null   # warm the cache in this shell
        verdict=$(resolve_item_for_path "$vault" "$rel" "$claimed")
        action="${verdict%% *}"
        id="${verdict#* }"

        case "$action" in
            found|adopt)
                mkdir -p "$(dirname "$rel")"
                if op document get "$id" --vault "$vault" --out-file "$rel" --force; then
                    claimed="${claimed:+$claimed,}$id"
                    echo "[+] $rel (from $vault, document '$title')"
                else
                    echo "[!] Could not fetch document '$title' from '$vault' for $rel"
                fi
                ;;
            none)
                echo "[!] No document in '$vault' for $rel (title '$title')"
                ;;
            ambiguous)
                echo "[!] Multiple documents titled '$title' in '$vault' and none matches path '$rel' — skipping. Run '$CLI_NAME write' to stamp items, or set the 'path' field manually."
                ;;
        esac
    done

    # Pattern entries: match stored 'path' fields across the vault's items and
    # download each hit to its stamped path. Items without the field can't
    # match a pattern; the safety gate keeps remote-supplied destinations
    # inside the repo.
    local pat regex matched rpath
    for entry in "${pattern_vaults[@]+"${pattern_vaults[@]}"}"; do
        pat="${entry%:*}"
        vault="${entry##*:}"

        if [[ -n "$vault_filter" && "$vault" != "$vault_filter" ]]; then
            continue
        fi
        if ! can_access_vault "$vault"; then
            echo "[!] No access to '$vault', skipping pattern $pat"
            continue
        fi

        regex=$(glob_to_regex "$(normalize_pattern "$pat")")
        get_vault_items "$vault" > /dev/null   # warm the cache in this shell
        matched=0
        while IFS=$'\t' read -r id rpath; do
            [[ -z "$id" ]] && continue
            printf '%s\n' "$rpath" | grep -Eq "$regex" || continue
            matched=$((matched + 1))
            case ",$claimed," in *",$id,"*) continue ;; esac
            if ! is_safe_rel_path "$rpath"; then
                echo "[!] Refusing unsafe path from document in '$vault': $rpath"
                continue
            fi
            mkdir -p "$(dirname "$rpath")"
            if op document get "$id" --vault "$vault" --out-file "$rpath" --force; then
                claimed="${claimed:+$claimed,}$id"
                echo "[+] $rpath (from $vault, pattern '$pat')"
            else
                echo "[!] Could not fetch document for $rpath from '$vault'"
            fi
        done < <(get_vault_items "$vault" | jq -r '.[] | . as $it | (.fields // [])[]
            | select(.label == "path") | [$it.id, .value] | @tsv')
        if [[ "$matched" -eq 0 ]]; then
            echo "[!] Pattern matched no documents in '$vault': $pat"
        fi
    done

    echo
    echo "Done!"
    return 0
}
