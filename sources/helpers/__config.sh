#!/usr/bin/env bash
# sources/helpers/__config.sh
# shellcheck disable=SC2034
# Finds and parses secrets.config.json into bash vars/arrays.
# Produces: platform, path (strings); vaults (vault names); file_vaults ("pattern:vault").

# Locates the config file in the current directory.
# Echoes the resolved path on success.
find_config() {
    if [[ -f "$CONFIG_FILE_NAME" ]]; then
        echo "$PWD/$CONFIG_FILE_NAME"
        return 0
    fi
    return 1
}

# Loads config from an explicit path (arg) or by locating it. Sets globals.
load_config() {
    local config_path="${1:-}"

    if [[ -z "$config_path" ]]; then
        if ! config_path=$(find_config); then
            echo "Error: $CONFIG_FILE_NAME not found. Run '$CLI_NAME init' first." >&2
            return 1
        fi
    fi

    if ! jq empty "$config_path" >/dev/null 2>&1; then
        echo "Error: $config_path is not valid JSON." >&2
        return 1
    fi

    local key
    for key in platform path vaults; do
        if ! jq -e "has(\"$key\")" "$config_path" >/dev/null 2>&1; then
            echo "Error: config missing required key '$key' in $config_path." >&2
            return 1
        fi
    done

    # Every vault entry must have a name and a non-empty patterns array.
    if ! jq -e '.vaults | type == "array" and length > 0
                and all(.[]; (.name | type == "string" and length > 0)
                             and (.patterns | type == "array" and length > 0))' \
            "$config_path" >/dev/null 2>&1; then
        echo "Error: each vault in $config_path needs a non-empty 'name' and 'patterns'." >&2
        return 1
    fi

    platform=$(jq -r '.platform' "$config_path")
    path=$(jq -r '.path' "$config_path")

    # Vault names (used for access detection / filtering).
    vaults=()
    while IFS= read -r line; do vaults+=("$line"); done \
        < <(jq -r '.vaults[].name' "$config_path")

    # Flatten to "pattern:vault" entries, preserving vault + pattern order so
    # first-match-wins is deterministic. Consumed by get_vault_for_file.
    file_vaults=()
    while IFS= read -r line; do file_vaults+=("$line"); done \
        < <(jq -r '.vaults[] | .name as $v | .patterns[] | . + ":" + $v' "$config_path")

    return 0
}
