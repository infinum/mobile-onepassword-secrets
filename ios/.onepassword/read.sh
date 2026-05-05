#!/usr/bin/env bash

set -e

# Load shared configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/utils.sh"

usage() {
    echo "Usage: $0 [-h] [vault]"
    echo
    echo "Downloads secret files from 1Password into the local vault directory."
    echo
    echo "Arguments:"
    echo "  vault   Optional. Filter downloads to a specific vault."
    echo "          Available: ${vaults[*]}"
    echo
    echo "Options:"
    echo "  -h      Show this help message and exit."
    return 0
}

# Resolves a CLI vault arg to a configured vault name (case-insensitive). Echoes the matched vault on success.
resolve_vault_filter() {
    local arg="$1"
    local arg_lc vault vault_lc
    arg_lc=$(to_lower "$arg")
    for vault in "${vaults[@]}"; do
        vault_lc=$(to_lower "$vault")
        if [[ "$vault_lc" == "$arg_lc" ]]; then
            echo "$vault"
            return 0
        fi
    done
    return 1
}

# Downloads <basename>.<env>.<ext> for each env in the given list.
# Usage: generate_files <vault_filter> <filename> <env...>
generate_files() {
    local vault_filter="$1"
    local file_arg="$2"
    shift 2
    local fields=("$@")

    local extension="${file_arg##*.}"
    local name
    name=$(basename -s ".$extension" "$file_arg")
    mkdir -p "$path/$name"

    local field
    for field in "${fields[@]}"; do
        local out_file="$name.$field.$extension"

        local vault mapped_vault
        if mapped_vault=$(get_vault_for_file "$out_file"); then
            vault="$mapped_vault"
        else
            echo "[!] No vault mapping for $out_file, skipping"
            continue
        fi

        if [[ -n "$vault_filter" && "$vault" != "$vault_filter" ]]; then
            continue
        fi

        if ! can_access_vault "$vault"; then
            echo "[!] No access to '$vault', skipping $out_file"
            continue
        fi

        local doc_name="${out_file%.*}"
        op document get "$doc_name" --out-file "$path/$name/$out_file" --vault "$vault" --force
        echo "[+] $out_file (from $vault)"
    done
    return 0
}

main() {
    local arg="${1:-}"
    mkdir -p "$path"

    local vault_filter=""
    if [[ -n "$arg" ]]; then
        if [[ "$arg" == "-h" || "$arg" == "--help" ]]; then
            usage; exit 0
        fi
        if ! vault_filter=$(resolve_vault_filter "$arg"); then
            echo "Invalid vault argument: $arg"
            echo
            usage
            exit 1
        fi
        echo "Filtering to vault: $vault_filter"
        echo
    fi

    detect_vault_access can_access_vault "read" "$vault_filter"
    echo

    echo "Fetching configurations..."
    echo

    if [[ "${#files[@]}" -eq 0 ]]; then
        echo "[!] No files configured in config.sh (files=())"
        exit 1
    fi

    local entry name envs_csv
    local -a envs
    for entry in "${files[@]}"; do
        name="${entry%:*}"
        envs_csv="${entry##*:}"
        if [[ "$envs_csv" == "*" ]]; then
            envs=("${environments[@]}")
        else
            IFS=',' read -r -a envs <<< "$envs_csv"
        fi
        generate_files "$vault_filter" "$name" "${envs[@]}"
    done

    echo
    echo "Done!"
    return 0
}

main "$@"
