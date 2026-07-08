#!/usr/bin/env bash
# sources/helpers/__platform.sh
# Platform hooks. iOS is implemented; Android is scaffolded (validation stub).

# Suggested default 'path' for `init`, by platform.
platform_default_path() {
    case "$1" in
        ios)     echo "ProjectName/SupportingFiles/Vault" ;;
        android) echo "app/src/main/secrets" ;;
        *)       echo "" ;;
    esac
}

# Gate for read/write. iOS passes; Android is an explicit not-implemented stub.
platform_validate() {
    case "$1" in
        ios)
            return 0
            ;;
        android)
            echo "Error: Android support is not yet implemented." >&2
            echo "The config seam exists; the read/write path is iOS-only for now." >&2
            return 1
            ;;
        *)
            echo "Error: unknown platform '$1' (expected 'ios' or 'android')." >&2
            return 1
            ;;
    esac
}
