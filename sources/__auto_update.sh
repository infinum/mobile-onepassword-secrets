#!/usr/bin/env bash
# __auto_update — re-run the installer to pull the latest version.
# shellcheck disable=SC2154
# CLI_NAME is a runtime global set in __constants.sh before this file is sourced.

__script_auto_update() {
    echo "Updating $CLI_NAME to the latest version..."
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/infinum/mobile-onepassword-secrets/main/install.sh)" -- --silent
}
