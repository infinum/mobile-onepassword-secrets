#!/usr/bin/env bash
# sources/helpers/__config.sh
# shellcheck disable=SC2034
# Finds and parses secrets.config.json into bash vars/arrays.
# Produces: vaults (1Password vault names); file_vaults ("relpath:vault");
#           vault_aliases ("label:vault" and "vault:vault" for filtering).

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

    if ! jq -e 'has("vaults")' "$config_path" >/dev/null 2>&1; then
        echo "Error: config missing required key 'vaults' in $config_path." >&2
        return 1
    fi

    # Every vault entry needs a non-empty 'vault' name and non-empty 'files'.
    if ! jq -e '.vaults | type == "array" and length > 0
                and all(.[]; (.vault | type == "string" and length > 0)
                             and (.files | type == "array" and length > 0))' \
            "$config_path" >/dev/null 2>&1; then
        echo "Error: each vault in $config_path needs a non-empty 'vault' and 'files'." >&2
        return 1
    fi

    # 1Password vault names (used for access detection / the doctor table).
    vaults=()
    while IFS= read -r line; do vaults+=("$line"); done \
        < <(jq -r '.vaults[].vault' "$config_path")

    # "relpath:vault" per file. Consumed by read (fetch) and write (route).
    file_vaults=()
    while IFS= read -r line; do file_vaults+=("$line"); done \
        < <(jq -r '.vaults[] | .vault as $v | .files[] | . + ":" + $v' "$config_path")

    # "alias:vault" for the optional friendly name and the vault name itself,
    # so `read <name>` and `read <vault>` both resolve.
    vault_aliases=()
    while IFS= read -r line; do vault_aliases+=("$line"); done \
        < <(jq -r '.vaults[] | .vault as $v | ((.name // $v) + ":" + $v), ($v + ":" + $v)' "$config_path")

    return 0
}
