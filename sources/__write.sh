#!/usr/bin/env bash
# __write — uploads secret files from a local directory to 1Password.
# shellcheck disable=SC2154
# SC2154: path, environments, platform, CLI_NAME, bold, reset are runtime-injected
# globals (loaded by load_config / setup_styles / entry point or tests).

__write_usage() {
    echo "Usage: $CLI_NAME write [-h] [directory]"
    echo
    echo "Uploads secret files from a local directory to 1Password."
    echo
    echo "Arguments:"
    echo "  directory   Optional. Name of the directory inside the configured path."
    echo "              If omitted, you will be prompted interactively."
    echo
    echo "Options:"
    echo "  -h          Show this help message and exit."
    return 0
}

# Returns the matching environment for a filename, anchored on dots, else non-zero.
match_environment() {
    local file_name="$1"
    local env
    for env in "${environments[@]+"${environments[@]}"}"; do
        if [[ ".$file_name." == *.${env}.* ]]; then
            echo "$env"
            return 0
        fi
    done
    return 1
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

    echo
    echo "==============================================================="
    echo "To write the files, specify which directory contains those files"
    echo "It will create appropriate 1password structure based on that information"
    echo
    echo "${bold}NOTE:${reset} The directory itself must be placed inside '$path'"

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

    local vault
    for vault in "${needed_vaults[@]}"; do
        detect_vault_access can_write_vault "write" "$vault"
    done

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
            echo "Name must contain one of the following environment descriptions: ${environments[*]+"${environments[*]}"}"
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
