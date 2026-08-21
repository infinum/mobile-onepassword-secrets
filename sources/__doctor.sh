#!/usr/bin/env bash
# shellcheck disable=SC2154
# SC2154: green, red, reset, vaults, CLI_NAME, CONFIG_FILE_NAME are runtime
#         globals injected by setup_styles / load_config / __constants.sh.
# __doctor — diagnose environment, config, and vault access. (alias: status)

__doctor() {
    setup_styles
    local ok="${green}✓${reset}"
    local bad="${red}✗${reset}"
    local failures=0

    local title="$CLI_NAME doctor"
    echo "$title"
    echo "${title//?/=}"
    echo

    # 1. Tooling. jq is a guaranteed Homebrew dependency, so only op is checked
    #    here — it's cask-only, and Homebrew formulae can't auto-install a cask.
    echo "Tooling:"
    local op_installed=true
    if ! report_tool op; then
        failures=$((failures + 1))
        op_installed=false
    fi
    echo

    # 2. 1Password sign-in. Bounded so a locked/unresponsive op can't hang doctor.
    echo "1Password session:"
    local signed_in=false
    if [[ "$op_installed" = true ]]; then
        local rc=0
        op_signed_in 8 || rc=$?
        if [[ "$rc" -eq 0 ]]; then
            if is_service_account; then
                echo "  $ok signed in (service account)"
            else
                echo "  $ok signed in"
            fi
            signed_in=true
        elif [[ "$rc" -eq 124 ]]; then
            echo "  $bad 1Password did not respond in time — unlock the 1Password app, then run 'op signin'"
            failures=$((failures + 1))
        elif op_bounded 8 op vault list; then
            # `op whoami` only reports an established session; real commands
            # can still authorize through the desktop-app integration.
            echo "  $ok signed in (via 1Password app integration)"
            signed_in=true
        else
            echo "  $bad not signed in — run 'op signin' (or set OP_SERVICE_ACCOUNT_TOKEN)"
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
        echo "  $ok valid ($((${#vaults[@]})) vault(s) configured)"
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
    if [[ "$signed_in" = true ]]; then
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
