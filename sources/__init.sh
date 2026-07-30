#!/usr/bin/env bash
# shellcheck disable=SC2154
# SC2154: CLI_NAME, CONFIG_FILE_NAME are runtime globals injected by the entry
#         point before this file is sourced.
# __init — scaffold secrets.config.json in the current directory.

__init() {
    local force=false

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --force)
                force=true; shift ;;
            -h|--help)
                echo "Usage: $CLI_NAME init [--force]"
                return 0 ;;
            *)
                echo "Unknown init option: $1" >&2; return 1 ;;
        esac
    done

    local target="$PWD/$CONFIG_FILE_NAME"
    if [[ -f "$target" && "$force" != true ]]; then
        echo "Error: $CONFIG_FILE_NAME already exists in this directory." >&2
        echo "Use --force to overwrite." >&2
        return 1
    fi

    cat > "$target" <<'EOF'
{
  "vaults": [
    {
      "name": "staging",
      "vault": "project-projectname-staging",
      "files": ["path/to/Secrets.staging.ext"]
    },
    {
      "name": "production",
      "vault": "project-projectname",
      "files": ["path/to/Secrets.production.ext"]
    }
  ]
}
EOF

    echo "Created $CONFIG_FILE_NAME."
    echo "Edit it to set your vault names and file paths, then run '$CLI_NAME doctor'."
    return 0
}
