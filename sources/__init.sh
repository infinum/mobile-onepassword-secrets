#!/usr/bin/env bash
# shellcheck disable=SC2154
# SC2154: CLI_NAME, CONFIG_FILE_NAME are runtime globals injected by the entry
#         point before this file is sourced.
# __init — scaffold secrets.config.json in the current directory.

# Best-effort open of the freshly created config. Never fails init.
# Opener resolution:
#   1. $INFINUM_SECRETS_OPENER — explicit override, always honored.
#   2. $VISUAL / $EDITOR, then `open` (macOS) / `xdg-open` (Linux) — but only
#      when attached to an interactive terminal (so CI never tries to open).
__init_open() {
    local file="$1"
    local opener="${INFINUM_SECRETS_OPENER:-}"
    if [[ -n "$opener" ]]; then
        # shellcheck disable=SC2086
        $opener "$file" || true
        return 0
    fi

    [[ -t 0 ]] || return 0

    opener="${VISUAL:-${EDITOR:-}}"
    if [[ -n "$opener" ]]; then
        # shellcheck disable=SC2086
        $opener "$file" || true
    elif command -v open > /dev/null 2>&1; then
        open "$file" || true
    elif command -v xdg-open > /dev/null 2>&1; then
        xdg-open "$file" > /dev/null 2>&1 || true
    fi
}

__init() {
    local force=false
    local open_after=true

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --force)
                force=true; shift ;;
            --no-open)
                open_after=false; shift ;;
            -h|--help)
                echo "Usage: $CLI_NAME init [--force] [--no-open]"
                echo
                echo "Creates a $CONFIG_FILE_NAME template in the current directory"
                echo "and opens it in your editor."
                echo
                echo "Options:"
                echo "  --force     Overwrite an existing $CONFIG_FILE_NAME."
                echo "  --no-open   Do not open the file after creating it."
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
    if [[ "$open_after" == true ]]; then
        __init_open "$target"
    fi
    return 0
}
