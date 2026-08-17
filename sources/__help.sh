#!/usr/bin/env bash
# __help — top-level usage.
# shellcheck disable=SC2154
# SC2154: CLI_NAME and CONFIG_FILE_NAME are runtime-injected globals
# (loaded from __constants.sh via the entry point).

__help() {
    cat << EOF
Usage: $CLI_NAME <command> [arguments]

Manages project secrets stored in 1Password, driven by $CONFIG_FILE_NAME.

Commands:
  init [--force] Scaffold $CONFIG_FILE_NAME in the current directory.
  read [vault]   Download each configured file from its vault to its path.
                 Optionally filter to a single vault (name or label).
  write [vault]  Upload each configured file to its vault.
                 Optionally filter to a single vault (name or label).
  doctor         Diagnose setup: signed in, config valid, and per-vault
                 read/write access. (alias: status)

Options:
  -h, --help    Show this help message.
  -v, --version Show the installed version.

Examples:
  $CLI_NAME init
  $CLI_NAME doctor
  $CLI_NAME read
  $CLI_NAME read staging
  $CLI_NAME write production
EOF
    return 0
}
