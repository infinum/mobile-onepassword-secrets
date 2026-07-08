#!/usr/bin/env bash
# shellcheck disable=SC2154
# SC2154: green, red, reset, platform, CLI_NAME, CONFIG_FILE_NAME are runtime
#         globals injected by setup_styles / load_config / __constants.sh.
# __doctor — diagnose environment, config, and vault access. (alias: status)

__doctor() {
    setup_styles
    local ok="${green}✓${reset}"
    local bad="${red}✗${reset}"
    local failures=0

    echo "infinum-secrets doctor"
    echo "======================"
    echo

    # 1. Tooling
    echo "Tooling:"
    if command -v op >/dev/null 2>&1; then
        echo "  $ok op (1Password CLI) installed"
    else
        echo "  $bad op not installed — brew install --cask 1password-cli"
        failures=$((failures + 1))
    fi
    if command -v jq >/dev/null 2>&1; then
        echo "  $ok jq installed"
    else
        echo "  $bad jq not installed — brew install jq"
        failures=$((failures + 1))
    fi
    echo

    # 2. 1Password sign-in (only if op present)
    echo "1Password session:"
    if command -v op >/dev/null 2>&1; then
        if op user get --me >/dev/null 2>&1; then
            echo "  $ok signed in"
        else
            echo "  $bad not signed in — run 'op signin'"
            failures=$((failures + 1))
        fi
    else
        echo "  - skipped (op not installed)"
    fi
    echo

    # 3. Config
    echo "Config:"
    local config_path
    if ! config_path=$(find_config); then
        echo "  $bad $CONFIG_FILE_NAME not found — run '$CLI_NAME init'"
        failures=$((failures + 1))
        echo
        echo "Result: $failures problem(s) found."
        [[ "$failures" -eq 0 ]]; return
    fi
    echo "  $ok found at $config_path"

    if ! jq empty "$config_path" >/dev/null 2>&1; then
        echo "  $bad config is not valid JSON"
        failures=$((failures + 1))
        echo
        echo "Result: $failures problem(s) found."
        [[ "$failures" -eq 0 ]]; return
    fi
    echo "  $ok valid JSON"

    if load_config "$config_path" >/dev/null 2>&1; then
        echo "  $ok all required keys present (platform: $platform)"
    else
        echo "  $bad config invalid:"
        load_config "$config_path" 2>&1 | sed 's/^/      /'
        failures=$((failures + 1))
        echo
        echo "Result: $failures problem(s) found."
        [[ "$failures" -eq 0 ]]; return
    fi
    echo

    # 4. Vault access (needs op + sign-in)
    echo "Vault access (read):"
    if command -v op >/dev/null 2>&1 && op user get --me >/dev/null 2>&1; then
        print_vault_access can_access_vault
        echo
        echo "Vault access (write):"
        print_vault_access can_write_vault
    else
        echo "  - skipped (op missing or not signed in)"
    fi
    echo

    echo "Result: $failures problem(s) found."
    [[ "$failures" -eq 0 ]]
}
