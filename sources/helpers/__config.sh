#!/usr/bin/env bash
# sources/helpers/__config.sh
# shellcheck disable=SC2034
# Finds and parses .secrets.config.json into bash vars/arrays.
# Produces: vaults (1Password vault names); file_vaults ("relpath:vault");
#           pattern_vaults ("pattern:vault" for glob/folder entries);
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

    # Every vault entry needs a non-empty 'vault' name and non-empty 'files',
    # and every 'files' entry must itself be a non-empty string — a number or
    # object here would sail through the path checks below (jq errors out on
    # them, which reads as "no match") and only break at fetch time.
    if ! jq -e '.vaults | type == "array" and length > 0
                and all(.[]; (.vault | type == "string" and length > 0)
                             and ((.name // "") | type == "string")
                             and (.files | type == "array" and length > 0)
                             and all(.files[]; type == "string" and length > 0))' \
            "$config_path" >/dev/null 2>&1; then
        echo "Error: each vault in $config_path needs a non-empty 'vault' and a 'files' list of non-empty strings." >&2
        return 1
    fi

    # ':' separates the fields in the "relpath:vault" and "label:vault"
    # encodings below, so a colon anywhere in a vault name or label would
    # silently reroute entries.
    if jq -e '[.vaults[] | .vault, (.name // empty)] | any(contains(":"))' \
            "$config_path" >/dev/null 2>&1; then
        echo "Error: vault names and labels must not contain ':' in $config_path." >&2
        return 1
    fi

    # Paths must stay inside the repo, not read as CLI flags (leading '-'),
    # and be ':'-free. Components are checked after dropping the folder
    # shorthand's trailing slash, so 'Certs/' passes but './x', 'a/./b' and
    # 'a//b' don't — those normalize to a different string than the one that
    # would be stamped on the item, which would then never match on read.
    if jq -e '[.vaults[].files[]] | any(startswith("/") or startswith("~")
              or startswith("-") or contains(":")
              or (sub("/$"; "") | split("/")
                  | any(. == ".." or . == "." or . == "")))' \
            "$config_path" >/dev/null 2>&1; then
        echo "Error: 'files' entries must be repo-relative paths without '.', '..', '//' or ':' (and not start with '-') in $config_path." >&2
        return 1
    fi

    # The distinct 1Password vaults (used for access detection and the doctor
    # table), in first-seen order. Several entries may share a vault — two
    # environments pointing at one staging vault, say — and each vault should
    # be listed and access-checked once, not once per entry.
    vaults=()
    while IFS= read -r line; do vaults+=("$line"); done \
        < <(jq -r '[.vaults[].vault]
                   | reduce .[] as $v ([]; if index($v) then . else . + [$v] end)
                   | .[]' "$config_path")

    # "relpath:vault" per literal file, "pattern:vault" per glob/folder entry.
    # Consumed by read (fetch/match) and write (route/expand).
    file_vaults=()
    pattern_vaults=()
    while IFS= read -r line; do
        if is_glob_entry "${line%:*}"; then
            pattern_vaults+=("$line")
        else
            file_vaults+=("$line")
        fi
    done < <(jq -r '.vaults[] | .vault as $v | .files[] | . + ":" + $v' "$config_path")

    # "alias:vault" for the optional friendly name and the vault name itself,
    # so `read <name>` and `read <vault>` both resolve.
    vault_aliases=()
    while IFS= read -r line; do vault_aliases+=("$line"); done \
        < <(jq -r '.vaults[] | .vault as $v | ((.name // $v) + ":" + $v), ($v + ":" + $v)' "$config_path")

    return 0
}
