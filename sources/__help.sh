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
  init [--platform <ios|android>] [--force]
                Scaffold $CONFIG_FILE_NAME in the current directory.
  read [vault]  Download secret files from 1Password into the local path.
                Optionally filter to a single vault.
  write [dir]   Upload secret files from a local directory to 1Password.
                Prompts interactively if no directory is given.
  doctor        Diagnose setup: op/jq installed, signed in, config valid,
                and per-vault read/write access. (alias: status)

Options:
  -h, --help    Show this help message.
  -v, --version Show the installed version.
  --update      Update $CLI_NAME to the latest version.

Examples:
  $CLI_NAME init --platform ios
  $CLI_NAME doctor
  $CLI_NAME read
  $CLI_NAME read project-x-ios-staging
  $CLI_NAME write MyLocalSecretsDir
EOF
    return 0
}
