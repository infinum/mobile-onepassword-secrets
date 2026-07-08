#!/usr/bin/env bash
# shellcheck disable=SC2154
# SC2154: CLI_NAME, CONFIG_FILE_NAME, SOURCES_DIR are runtime globals
#         injected by the entry point before this file is sourced.
# __init — scaffold secrets.config.json in the current directory.

__init() {
    local platform="ios"
    local force=false

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --platform)
                platform="${2:-}"; shift 2 ;;
            --force)
                force=true; shift ;;
            -h|--help)
                echo "Usage: $CLI_NAME init [--platform <ios|android>] [--force]"
                return 0 ;;
            *)
                echo "Unknown init option: $1" >&2; return 1 ;;
        esac
    done

    if [[ "$platform" != "ios" && "$platform" != "android" ]]; then
        echo "Error: --platform must be 'ios' or 'android'." >&2
        return 1
    fi

    local target="$PWD/$CONFIG_FILE_NAME"
    if [[ -f "$target" && "$force" != true ]]; then
        echo "Error: $CONFIG_FILE_NAME already exists in this directory." >&2
        echo "Use --force to overwrite." >&2
        return 1
    fi

    if ! command -v jq >/dev/null 2>&1; then
        echo "Error: 'jq' is required but not installed." >&2
        echo "Install with: brew install jq" >&2
        return 1
    fi

    local template="$SOURCES_DIR/$CONFIG_FILE_NAME"
    if [[ ! -f "$template" ]]; then
        echo "Error: config template not found at $template." >&2
        return 1
    fi

    local default_path
    default_path=$(platform_default_path "$platform")

    jq --arg platform "$platform" --arg path "$default_path" \
        '.platform = $platform | .path = $path' "$template" > "$target"

    echo "Created $CONFIG_FILE_NAME (platform: $platform)."
    echo "Edit it to set your vaults, files, and path, then run '$CLI_NAME doctor'."
    return 0
}
