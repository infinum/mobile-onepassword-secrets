#!/usr/bin/env bash
# __write — uploads secret files from the local path to 1Password.
# shellcheck disable=SC2154
# SC2154: path, platform, CLI_NAME, bold, reset are runtime-injected globals
# (loaded by load_config / setup_styles / entry point or tests).

__write_usage() {
    echo "Usage: $CLI_NAME write [-h] [subdir]"
    echo
    echo "Uploads secret files to 1Password. Each file under the configured path is"
    echo "routed to a vault by matching its path (relative to the configured path)"
    echo "against the vault patterns; the relative path becomes the document title."
    echo
    echo "Arguments:"
    echo "  subdir   Optional. Restrict the upload to a subdirectory of the path."
    echo
    echo "Options:"
    echo "  -h       Show this help message and exit."
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
    platform_validate "$platform" || exit 1

    clear 2>/dev/null || true
    echo
    echo "###############################################################"
    echo "                       SECRET WRITE SCRIPT                     "
    echo "###############################################################"
    echo

    echo "Before you proceed, make sure that you have the latest files locally."
    read -r -e -p "Have you pulled the files from 1Password? Press enter to continue, or 'q' to quit: " response
    [[ $response == q ]] && { echo "No problem! Come back again after you've updated the files."; exit; }

    local root="$path"
    if [[ -n "$arg" ]]; then
        root="$path/$arg"
        if [[ ! -e "$root" ]]; then
            echo "$root does not exist."
            exit 1
        fi
    fi
    if [[ ! -d "$path" ]]; then
        echo "Configured path '$path' does not exist."
        exit 1
    fi

    # Route each file to a vault by matching its path relative to $path.
    echo
    local -a mapped_files=() mapped_vaults=() needed_vaults=()
    local f relpath v added existing
    while IFS= read -r f; do
        relpath="${f#"$path"/}"
        if v=$(get_vault_for_file "$relpath"); then
            mapped_files+=("$relpath")
            mapped_vaults+=("$v")
            added=false
            for existing in "${needed_vaults[@]+"${needed_vaults[@]}"}"; do
                [[ "$existing" == "$v" ]] && { added=true; break; }
            done
            [[ "$added" = false ]] && needed_vaults+=("$v")
        else
            echo "[!] No vault mapping for $relpath, skipping"
        fi
    done < <(find "$root" -type f | sort)

    if [[ "${#mapped_files[@]}" -eq 0 ]]; then
        echo "No files matched any vault pattern under '$root'."
        exit 1
    fi

    # Check write access only for the vaults actually needed.
    local vault
    for vault in "${needed_vaults[@]}"; do
        detect_vault_access can_write_vault "write" "$vault"
    done

    # Preview.
    echo
    local i has_files=false
    for i in "${!mapped_files[@]}"; do
        relpath="${mapped_files[$i]}"
        v="${mapped_vaults[$i]}"
        if can_write_vault "$v"; then
            echo "[+] $relpath → $v"
            has_files=true
        else
            echo "[!] $relpath → $v (no write access, will skip)"
        fi
    done

    if [[ "$has_files" = false ]]; then
        echo
        echo "No files to upload (no vault access)."
        exit 1
    fi

    echo
    read -r -e -p "Are those the files you want to upload? Press enter to continue, or 'q' to quit: " response
    [[ $response == q ]] && { echo "Okay, you can try again with different ones."; exit; }

    echo
    echo "Uploading..."
    echo

    for i in "${!mapped_files[@]}"; do
        relpath="${mapped_files[$i]}"
        v="${mapped_vaults[$i]}"
        can_write_vault "$v" || continue

        # The relative path is the document title, so read can restore it exactly.
        if op item get "$relpath" --vault "$v" > /dev/null 2>&1; then
            op document edit "$relpath" "$path/$relpath" --vault "$v"
        else
            op document create "$path/$relpath" --title "$relpath" --vault "$v"
        fi
        echo "[+] $relpath → $v"
    done

    echo
    echo "Done!"
    return 0
}
