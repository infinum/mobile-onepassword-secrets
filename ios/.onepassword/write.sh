#!/usr/bin/env bash

set -e

# Load shared configuration (also defines bold/normal)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/utils.sh"

usage() {
    echo "Usage: $0 [-h] [directory]"
    echo
    echo "Uploads secret files from a local directory to 1Password."
    echo
    echo "Arguments:"
    echo "  directory   Optional. Name of the directory inside '$path' to upload."
    echo "              If omitted, you will be prompted interactively."
    echo
    echo "Options:"
    echo "  -h          Show this help message and exit."
    return 0
}

# Returns the matching environment from $environments for a given filename, or empty.
# Match is anchored on dots, e.g. "Keys.production.swift" matches "production".
match_environment() {
    local file_name="$1"
    local env
    for env in "${environments[@]}"; do
        if [[ ".$file_name." == *.${env}.* ]]; then
            echo "$env"
            return 0
        fi
    done
    return 1
}

main() {
    local arg="${1:-}"
    if [[ "$arg" == "-h" || "$arg" == "--help" ]]; then
        usage; exit 0
    fi

    clear
    echo
    echo "###############################################################"
    echo "                       SECRET WRITE SCRIPT                     "
    echo "###############################################################"
    echo

    echo "Before you proceed, make sure that you have the latest files locally."
    read -r -e -p "Have you pulled the files from 1Password? Press enter to continue, or 'q' to quit: " response
    [[ $response == q ]] && { echo "No problem! Come back again after you've updated the files."; exit; }

    echo
    echo "==============================================================="
    echo "To write the files, specify which directory contains those files"
    echo "It will create appropriate 1password structure based on that information"
    echo
    echo "${bold}NOTE:${normal} The directory itself must be placed inside '$path'"

    # Get directory from CLI arg or interactive prompt
    local dir="$arg"
    if [[ -n "$dir" ]]; then
        if [[ ! -d "$path/$dir" ]]; then
            echo "$path/$dir does not exist."
            exit 1
        fi
    else
        while read -r -e -p "Enter directory name: " dir && [[ ! -d "$path/$dir" ]]; do
            [[ $dir == q ]] && { echo "See you around."; exit; }
            echo
            echo "$path/$dir does not exist. To quit, enter 'q'."
        done
    fi

    # Determine which vaults are needed from file mappings
    echo
    local needed_vaults=()
    local file base_name mapped_vault
    for file in "$path/$dir"/*; do
        base_name=$(basename "$file")
        if mapped_vault=$(get_vault_for_file "$base_name"); then
            local already_added=false v
            for v in "${needed_vaults[@]+"${needed_vaults[@]}"}"; do
                [[ "$v" == "$mapped_vault" ]] && { already_added=true; break; }
            done
            [[ "$already_added" = false ]] && needed_vaults+=("$mapped_vault")
        else
            echo "[!] No vault mapping for $base_name, skipping"
        fi
    done

    if [[ "${#needed_vaults[@]}" -eq 0 ]]; then
        echo "No files with valid vault mappings found in '$dir'."
        exit 1
    fi

    # Check write access for only the vaults that are actually needed
    local vault
    for vault in "${needed_vaults[@]}"; do
        detect_vault_access can_write_vault "write" "$vault"
    done

    # Preview files with vault info and access status
    echo
    local has_files=false
    for file in "$path/$dir"/*; do
        base_name=$(basename "$file")
        if ! mapped_vault=$(get_vault_for_file "$base_name"); then
            continue
        fi

        if can_write_vault "$mapped_vault"; then
            echo "[+] $base_name → $mapped_vault"
            has_files=true
        else
            echo "[!] $base_name → $mapped_vault (no write access, will skip)"
        fi
    done

    if [[ "$has_files" = false ]]; then
        echo
        echo "No files to upload (no vault access or no mappings)."
        exit 1
    fi

    echo
    read -r -e -p "Are those the files you want to upload? Press enter to continue, or 'q' to quit: " response
    [[ $response == q ]] && { echo "Okay, you can try again with different ones."; exit; }

    echo
    echo "Uploading..."
    echo

    # Upload files
    local file_path doc_name
    for file_path in "$path/$dir"/*; do
        base_name=$(basename "$file_path")

        if ! mapped_vault=$(get_vault_for_file "$base_name"); then
            continue
        fi

        if ! can_write_vault "$mapped_vault"; then
            continue
        fi

        if ! match_environment "$base_name" > /dev/null; then
            echo
            echo "Validation failed for '$file_path'"
            echo "Name must contain one of the following environment descriptions: ${environments[*]}"
            echo "Those environments must be separated by dots, e.g. my_file.staging.json"
            exit 1
        fi

        doc_name="${base_name%.*}"
        if op item get "$doc_name" --vault "$mapped_vault" > /dev/null 2>&1; then
            op document edit "$doc_name" "$file_path" --vault "$mapped_vault"
        else
            op document create "$file_path" --title "$doc_name" --vault "$mapped_vault"
        fi
    done

    echo "Done!"
    return 0
}

main "$@"
