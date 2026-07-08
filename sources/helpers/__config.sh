#!/usr/bin/env bash
# sources/helpers/__config.sh
# shellcheck disable=SC2034
# Finds and parses secrets.config.json into bash vars/arrays.
# Produces: platform, path (strings); environments, vaults, files, file_vaults (arrays).

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
    for key in platform path environments vaults files fileVaults; do
        if ! jq -e "has(\"$key\")" "$config_path" >/dev/null 2>&1; then
            echo "Error: config missing required key '$key' in $config_path." >&2
            return 1
        fi
    done

    platform=$(jq -r '.platform' "$config_path")
    path=$(jq -r '.path' "$config_path")

    environments=()
    while IFS= read -r line; do environments+=("$line"); done \
        < <(jq -r '.environments[]' "$config_path")

    vaults=()
    while IFS= read -r line; do vaults+=("$line"); done \
        < <(jq -r '.vaults[]' "$config_path")

    files=()
    while IFS= read -r line; do files+=("$line"); done \
        < <(jq -r '.files[] | "\(.name):\(.environments | join(","))"' "$config_path")

    file_vaults=()
    while IFS= read -r line; do file_vaults+=("$line"); done \
        < <(jq -r '.fileVaults[] | "\(.pattern):\(.vault)"' "$config_path")

    return 0
}
