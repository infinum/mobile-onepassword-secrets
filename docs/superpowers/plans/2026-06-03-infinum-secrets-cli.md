# infinum-secrets CLI Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Wrap the existing 1Password bash scripts into an installable `infinum-secrets` CLI with `init`/`read`/`write`/`doctor` subcommands, JSON config, and a platform seam (iOS implemented, Android stubbed).

**Architecture:** A single entry point (`infinum-secrets.sh`) glob-sources a `sources/` library, then dispatches `$1` to `__<command>` bash functions. Per-project config is JSON (`secrets.config.json`) parsed by `jq` into the same bash arrays the current scripts consume. Read/write logic is shared; platform differences live behind hook functions in `helpers/__platform.sh`. Installed globally via a curl-pipe-to-bash installer; projects carry only the JSON config.

**Tech Stack:** Bash (3.2-compatible — macOS system bash; no `mapfile`, no `${var,,}`), `jq`, `op` (1Password CLI), `git`. Tests use [bats-core](https://github.com/bats-core/bats-core) for pure helpers; `op`-dependent commands are verified manually.

---

## Conventions

- **Bash 3.2 compatibility is mandatory.** Build arrays with `while IFS= read -r line; do arr+=("$line"); done < <(...)`, never `mapfile`/`readarray`. Lowercase via the `to_lower` helper, never `${var,,}`.
- **Runtime source dir** is resolved as `SOURCES_DIR="${INFINUM_SECRETS_SOURCES:-/usr/local/bin/.infinum-secrets-sources}"`. During development and tests, set `INFINUM_SECRETS_SOURCES=./sources`.
- Every command function is named `__<command>` and takes `"$@"`.
- Config arrays produced by the parser (consumed everywhere): `platform` (string), `path` (string), `environments` (array), `vaults` (array), `files` (array of `"name:csv"` / `"name:*"`), `file_vaults` (array of `"pattern:vault"`).

## File Structure

```
infinum-secrets.sh                  # entry point + dispatch (installs as infinum-secrets)
install.sh                          # curl-pipe installer
sources/
  __constants.sh                    # VERSION, names
  __help.sh                         # __help heredoc
  __init.sh                         # __init — scaffold config
  __read.sh                         # __read — download secrets
  __write.sh                        # __write — upload secrets
  __doctor.sh                       # __doctor — diagnostics
  __auto_update.sh                  # __script_auto_update — --update
  secrets.config.json               # config template (copied by init)
  helpers/
    __config.sh                     # find + parse JSON config → bash arrays
    __op_utils.sh                   # op/jq checks, vault access (from ios/utils.sh)
    __platform.sh                   # platform hooks (default path, validation)
tests/
  fixtures/valid.config.json
  config.bats
  op_utils.bats
  read.bats
  write.bats
  entry.bats
README.md
```

Old `ios/.onepassword/{config,utils,read,write}.sh` are removed in the final task.

---

### Task 0: Dev prerequisites

**Files:** none (environment setup)

- [ ] **Step 1: Install bats-core (test runner)**

Run: `brew install bats-core`
Expected: `bats` on PATH. Verify: `bats --version` prints e.g. `Bats 1.11.0`.

- [ ] **Step 2: Confirm jq present (already a runtime dep)**

Run: `jq --version`
Expected: prints e.g. `jq-1.7.1`. If missing: `brew install jq`.

---

### Task 1: Repo scaffold — constants + entry dispatch

**Files:**
- Create: `sources/__constants.sh`
- Create: `infinum-secrets.sh`
- Test: `tests/entry.bats`

- [ ] **Step 1: Write the constants file**

```bash
# sources/__constants.sh
#!/usr/bin/env bash
# shellcheck disable=SC2034
# (vars consumed by entry point + sourcing scripts)

VERSION="1.0.0"
CLI_NAME="infinum-secrets"
CONFIG_FILE_NAME="secrets.config.json"
```

- [ ] **Step 2: Write the entry point with glob-sourcing and dispatch**

```bash
# infinum-secrets.sh
#!/usr/bin/env bash

set -euo pipefail

# Resolve library dir. Installed default; override for dev/tests.
SOURCES_DIR="${INFINUM_SECRETS_SOURCES:-/usr/local/bin/.infinum-secrets-sources}"

if [[ ! -d "$SOURCES_DIR" ]]; then
    echo "Error: sources directory not found at $SOURCES_DIR" >&2
    echo "Reinstall infinum-secrets, or set INFINUM_SECRETS_SOURCES." >&2
    exit 1
fi

# Source helpers first, then top-level command files. Guard empty globs.
for _f in "$SOURCES_DIR"/helpers/*.sh "$SOURCES_DIR"/*.sh; do
    [[ -e "$_f" ]] || continue
    # shellcheck disable=SC1090
    source "$_f"
done

case "${1:-}" in
    -h|--help|help)
        __help
        ;;
    -v|--version)
        echo "$CLI_NAME $VERSION"
        ;;
    --update)
        __script_auto_update
        ;;
    init)
        shift
        __init "$@"
        ;;
    read)
        shift
        __read "$@"
        ;;
    write)
        shift
        __write "$@"
        ;;
    doctor|status)
        shift
        __doctor "$@"
        ;;
    "")
        echo "No command given. Try '$CLI_NAME --help'." >&2
        exit 1
        ;;
    *)
        echo "Unsupported command: $1" >&2
        echo "Try '$CLI_NAME --help'." >&2
        exit 1
        ;;
esac
```

- [ ] **Step 3: Write the failing entry test**

```bash
# tests/entry.bats
setup() {
    REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
    export INFINUM_SECRETS_SOURCES="$REPO_ROOT/sources"
    CLI="$REPO_ROOT/infinum-secrets.sh"
}

@test "--version prints name and version" {
    run bash "$CLI" --version
    [ "$status" -eq 0 ]
    [[ "$output" == "infinum-secrets "* ]]
}

@test "unsupported command exits non-zero" {
    run bash "$CLI" frobnicate
    [ "$status" -ne 0 ]
    [[ "$output" == *"Unsupported command: frobnicate"* ]]
}

@test "no command exits non-zero" {
    run bash "$CLI"
    [ "$status" -ne 0 ]
    [[ "$output" == *"No command given"* ]]
}
```

- [ ] **Step 4: Run the entry test**

Run: `bats tests/entry.bats`
Expected: 3 tests PASS. (`--help` is not tested yet; `__help` arrives in Task 7.)

- [ ] **Step 5: Commit**

```bash
git add sources/__constants.sh infinum-secrets.sh tests/entry.bats
git commit -m "feat: scaffold infinum-secrets entry point and dispatch"
```

---

### Task 2: Config parser (`helpers/__config.sh`)

**Files:**
- Create: `sources/helpers/__config.sh`
- Create: `tests/fixtures/valid.config.json`
- Test: `tests/config.bats`

- [ ] **Step 1: Write the fixture config**

```json
// tests/fixtures/valid.config.json
{
  "platform": "ios",
  "path": "ProjectName/SupportingFiles/Vault",
  "environments": ["production", "staging"],
  "vaults": ["project-projectname-ios", "project-projectname-ios-staging"],
  "files": [
    { "name": "Keys.swift", "environments": ["*"] },
    { "name": "Config.json", "environments": ["staging"] }
  ],
  "fileVaults": [
    { "pattern": "*.staging.*", "vault": "project-projectname-ios-staging" },
    { "pattern": "*.production.*", "vault": "project-projectname-ios" }
  ]
}
```

(Note: JSON has no comments — drop the `//` line when creating the file.)

- [ ] **Step 2: Write the failing config test**

```bash
# tests/config.bats
setup() {
    REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
    source "$REPO_ROOT/sources/__constants.sh"
    source "$REPO_ROOT/sources/helpers/__config.sh"
    FIXTURE="$REPO_ROOT/tests/fixtures/valid.config.json"
}

@test "load_config parses scalars" {
    load_config "$FIXTURE"
    [ "$platform" = "ios" ]
    [ "$path" = "ProjectName/SupportingFiles/Vault" ]
}

@test "load_config parses environments array" {
    load_config "$FIXTURE"
    [ "${#environments[@]}" -eq 2 ]
    [ "${environments[0]}" = "production" ]
    [ "${environments[1]}" = "staging" ]
}

@test "load_config parses vaults array" {
    load_config "$FIXTURE"
    [ "${#vaults[@]}" -eq 2 ]
    [ "${vaults[0]}" = "project-projectname-ios" ]
}

@test "load_config builds files as name:csv strings" {
    load_config "$FIXTURE"
    [ "${#files[@]}" -eq 2 ]
    [ "${files[0]}" = "Keys.swift:*" ]
    [ "${files[1]}" = "Config.json:staging" ]
}

@test "load_config builds file_vaults as pattern:vault strings" {
    load_config "$FIXTURE"
    [ "${#file_vaults[@]}" -eq 2 ]
    [ "${file_vaults[0]}" = "*.staging.*:project-projectname-ios-staging" ]
}

@test "load_config fails on invalid JSON" {
    tmp="$(mktemp)"
    echo "{ not json" > "$tmp"
    run load_config "$tmp"
    rm -f "$tmp"
    [ "$status" -ne 0 ]
    [[ "$output" == *"not valid JSON"* ]]
}

@test "load_config fails on missing required key" {
    tmp="$(mktemp)"
    echo '{"platform":"ios"}' > "$tmp"
    run load_config "$tmp"
    rm -f "$tmp"
    [ "$status" -ne 0 ]
    [[ "$output" == *"missing required key"* ]]
}
```

- [ ] **Step 3: Run test to verify it fails**

Run: `bats tests/config.bats`
Expected: FAIL — `load_config: command not found`.

- [ ] **Step 4: Write `helpers/__config.sh`**

```bash
# sources/helpers/__config.sh
#!/usr/bin/env bash
# Finds and parses secrets.config.json into bash vars/arrays.
# Produces: platform, path (strings); environments, vaults, files, file_vaults (arrays).

# Locates the config file. Honors $SECRETS_CONFIG override, else looks in CWD.
# Echoes the resolved path on success.
find_config() {
    if [[ -n "${SECRETS_CONFIG:-}" ]]; then
        [[ -f "$SECRETS_CONFIG" ]] && { echo "$SECRETS_CONFIG"; return 0; }
        return 1
    fi
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

    local key
    for key in platform path environments vaults files fileVaults; do
        if ! jq -e "has(\"$key\")" "$config_path" >/dev/null 2>&1; then
            echo "Error: config missing required key '$key' in $config_path." >&2
            return 1
        fi
    done

    platform=$(jq -r '.platform' "$config_path")
    path=$(jq -r '.path' "$config_path")

    environments=()
    while IFS= read -r line; do environments+=("$line"); done \
        < <(jq -r '.environments[]' "$config_path")

    vaults=()
    while IFS= read -r line; do vaults+=("$line"); done \
        < <(jq -r '.vaults[]' "$config_path")

    files=()
    while IFS= read -r line; do files+=("$line"); done \
        < <(jq -r '.files[] | "\(.name):\(.environments | join(","))"' "$config_path")

    file_vaults=()
    while IFS= read -r line; do file_vaults+=("$line"); done \
        < <(jq -r '.fileVaults[] | "\(.pattern):\(.vault)"' "$config_path")

    return 0
}
```

- [ ] **Step 5: Run test to verify it passes**

Run: `bats tests/config.bats`
Expected: all 7 tests PASS.

- [ ] **Step 6: Commit**

```bash
git add sources/helpers/__config.sh tests/fixtures/valid.config.json tests/config.bats
git commit -m "feat: add JSON config parser with jq"
```

---

### Task 3: 1Password helpers (`helpers/__op_utils.sh`)

**Files:**
- Create: `sources/helpers/__op_utils.sh`
- Test: `tests/op_utils.bats`

This ports `ios/.onepassword/utils.sh`, dropping its top-of-file `source config.sh` (config now comes from `__config.sh`). The `op`/`jq` presence checks move into a `require_tools` function so sourcing the file never exits (sourcing must stay side-effect-free for tests).

- [ ] **Step 1: Write the failing test for `get_vault_for_file`**

```bash
# tests/op_utils.bats
setup() {
    REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
    source "$REPO_ROOT/sources/__constants.sh"
    source "$REPO_ROOT/sources/helpers/__op_utils.sh"
    file_vaults=(
        "*.staging.*:vault-staging"
        "*.production.*:vault-prod"
    )
}

@test "get_vault_for_file matches staging pattern" {
    run get_vault_for_file "Keys.staging.swift"
    [ "$status" -eq 0 ]
    [ "$output" = "vault-staging" ]
}

@test "get_vault_for_file matches production pattern" {
    run get_vault_for_file "Keys.production.swift"
    [ "$status" -eq 0 ]
    [ "$output" = "vault-prod" ]
}

@test "get_vault_for_file returns non-zero when no match" {
    run get_vault_for_file "Keys.swift"
    [ "$status" -ne 0 ]
}

@test "to_lower lowercases" {
    run to_lower "ABC-Def"
    [ "$output" = "abc-def" ]
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bats tests/op_utils.bats`
Expected: FAIL — `get_vault_for_file: command not found`.

- [ ] **Step 3: Write `helpers/__op_utils.sh`**

```bash
# sources/helpers/__op_utils.sh
#!/usr/bin/env bash
# Helper functions for 1Password interaction. Sourcing is side-effect-free;
# call require_tools / setup_styles explicitly.

# Verifies required CLIs are installed. Call before any op-dependent command.
require_tools() {
    if ! command -v op >/dev/null 2>&1; then
        echo "Error: 1Password CLI 'op' is required but not installed." >&2
        echo "Install with: brew install --cask 1password-cli" >&2
        return 1
    fi
    if ! command -v jq >/dev/null 2>&1; then
        echo "Error: 'jq' is required but not installed." >&2
        echo "Install with: brew install jq" >&2
        return 1
    fi
    return 0
}

# Colors / styles. Gracefully degrade with no terminal (e.g. CI).
# shellcheck disable=SC2034
setup_styles() {
    green=$(tput setaf 2 2>/dev/null || true)
    red=$(tput setaf 1 2>/dev/null || true)
    bold=$(tput bold 2>/dev/null || true)
    reset=$(tput sgr0 2>/dev/null || true)
    normal="$reset"
}

# Lowercase a string portably (bash 3.2 has no ${var,,}).
to_lower() {
    printf '%s' "$1" | tr '[:upper:]' '[:lower:]'
}

# Returns the mapped vault for a filename by matching file_vaults entries.
# Each entry is "glob_pattern:vault". First match wins.
get_vault_for_file() {
    local file_name="$1"
    local entry pattern vault
    for entry in "${file_vaults[@]}"; do
        pattern="${entry%:*}"
        vault="${entry##*:}"
        # shellcheck disable=SC2053
        if [[ "$file_name" == $pattern ]]; then
            echo "$vault"
            return 0
        fi
    done
    return 1
}

_accessible_vaults=""
_current_user_id=""

# Newline-separated list of vault names the current user can see; cached.
get_accessible_vaults() {
    if [[ -z "$_accessible_vaults" ]]; then
        _accessible_vaults=$(op vault list --format=json 2>/dev/null | jq -r '.[].name')
    fi
    echo "$_accessible_vaults"
    return 0
}

# Current 1Password user ID; cached.
_get_current_user_id() {
    if [[ -z "$_current_user_id" ]]; then
        _current_user_id=$(op user get --me --format=json 2>/dev/null | jq -r '.id')
    fi
    echo "$_current_user_id"
    return 0
}

# Returns 0 if the current user has read access to the given vault.
can_access_vault() {
    local vault_name="$1"
    get_accessible_vaults | grep -qx "$vault_name"
    return $?
}

# Returns 0 if the current user has write (allow_editing) permission on the vault.
can_write_vault() {
    local vault_name="$1"
    local user_id
    user_id=$(_get_current_user_id)
    if [[ -z "$user_id" ]]; then
        return 1
    fi
    op vault user list "$vault_name" --format=json 2>/dev/null \
        | jq -e --arg uid "$user_id" '.[] | select(.id == $uid) | .permissions | index("allow_editing")' \
        > /dev/null 2>&1
}

# Prints each vault with a green check or red cross per the given check function.
print_vault_access() {
    local check_fn="$1"  # can_access_vault or can_write_vault
    local vault
    for vault in "${vaults[@]}"; do
        if $check_fn "$vault"; then
            echo "  ${green}✓${reset} $vault"
        else
            echo "  ${red}✗${reset} $vault"
        fi
    done
    return 0
}

# Detects vault access, prints status, exits if none accessible.
# Usage: detect_vault_access <check_fn> [label] [vault_filter]
detect_vault_access() {
    local check_fn="$1"
    local label="${2:-}"
    local vault_filter="${3:-}"

    echo "Detecting vault ${label} access..."
    if [[ -n "$vault_filter" ]]; then
        if ! $check_fn "$vault_filter"; then
            echo "  ${red}✗${reset} $vault_filter"
            echo
            echo "You don't have ${label} access to vault '$vault_filter'. Please check your access with the team."
            exit 1
        fi
        echo "  ${green}✓${reset} $vault_filter"
    else
        print_vault_access "$check_fn"
        local any_accessible=false vault
        for vault in "${vaults[@]}"; do
            $check_fn "$vault" && { any_accessible=true; break; }
        done
        if [[ "$any_accessible" = false ]]; then
            echo
            echo "You don't have ${label} access to any vault. Please check your access with the team."
            exit 1
        fi
    fi
    return 0
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bats tests/op_utils.bats`
Expected: 4 tests PASS.

- [ ] **Step 5: Commit**

```bash
git add sources/helpers/__op_utils.sh tests/op_utils.bats
git commit -m "feat: port 1Password helpers (op/jq utils, vault access)"
```

---

### Task 4: Platform hook (`helpers/__platform.sh`)

**Files:**
- Create: `sources/helpers/__platform.sh`
- Test: append to `tests/op_utils.bats` is not ideal; create `tests/platform.bats`

- [ ] **Step 1: Write the failing platform test**

```bash
# tests/platform.bats
setup() {
    REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
    source "$REPO_ROOT/sources/helpers/__platform.sh"
}

@test "platform_default_path returns ios path" {
    run platform_default_path ios
    [ "$status" -eq 0 ]
    [ "$output" = "ProjectName/SupportingFiles/Vault" ]
}

@test "platform_default_path returns android path" {
    run platform_default_path android
    [ "$output" = "app/src/main/secrets" ]
}

@test "platform_validate accepts ios" {
    run platform_validate ios
    [ "$status" -eq 0 ]
}

@test "platform_validate rejects android as not implemented" {
    run platform_validate android
    [ "$status" -ne 0 ]
    [[ "$output" == *"not yet implemented"* ]]
}

@test "platform_validate rejects unknown platform" {
    run platform_validate windows
    [ "$status" -ne 0 ]
    [[ "$output" == *"unknown platform"* ]]
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bats tests/platform.bats`
Expected: FAIL — `platform_default_path: command not found`.

- [ ] **Step 3: Write `helpers/__platform.sh`**

```bash
# sources/helpers/__platform.sh
#!/usr/bin/env bash
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
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bats tests/platform.bats`
Expected: 5 tests PASS.

- [ ] **Step 5: Commit**

```bash
git add sources/helpers/__platform.sh tests/platform.bats
git commit -m "feat: add platform hooks (iOS impl, Android stub)"
```

---

### Task 5: Read command (`__read.sh`)

**Files:**
- Create: `sources/__read.sh`
- Test: `tests/read.bats` (pure helper `resolve_vault_filter`); `op`-dependent flow verified manually.

This ports `ios/.onepassword/read.sh`: `main` → `__read`, config from `load_config`, tools/styles initialized explicitly, platform gated.

- [ ] **Step 1: Write the failing test for `resolve_vault_filter`**

```bash
# tests/read.bats
setup() {
    REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
    source "$REPO_ROOT/sources/__constants.sh"
    source "$REPO_ROOT/sources/helpers/__op_utils.sh"
    source "$REPO_ROOT/sources/__read.sh"
    vaults=("project-x-ios" "project-x-ios-staging")
}

@test "resolve_vault_filter matches case-insensitively" {
    run resolve_vault_filter "PROJECT-X-IOS"
    [ "$status" -eq 0 ]
    [ "$output" = "project-x-ios" ]
}

@test "resolve_vault_filter returns non-zero for unknown vault" {
    run resolve_vault_filter "nope"
    [ "$status" -ne 0 ]
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bats tests/read.bats`
Expected: FAIL — `resolve_vault_filter: command not found` (source error: file missing).

- [ ] **Step 3: Write `sources/__read.sh`**

```bash
# sources/__read.sh
#!/usr/bin/env bash
# __read — downloads secret files from 1Password into the local path.

__read_usage() {
    echo "Usage: $CLI_NAME read [-h] [vault]"
    echo
    echo "Downloads secret files from 1Password into the local vault directory."
    echo
    echo "Arguments:"
    echo "  vault   Optional. Filter downloads to a specific vault."
    echo
    echo "Options:"
    echo "  -h      Show this help message and exit."
    return 0
}

# Resolves a CLI vault arg to a configured vault name (case-insensitive).
resolve_vault_filter() {
    local arg="$1"
    local arg_lc vault vault_lc
    arg_lc=$(to_lower "$arg")
    for vault in "${vaults[@]}"; do
        vault_lc=$(to_lower "$vault")
        if [[ "$vault_lc" == "$arg_lc" ]]; then
            echo "$vault"
            return 0
        fi
    done
    return 1
}

# Downloads <basename>.<env>.<ext> for each env in the given list.
# Usage: __read_generate_files <vault_filter> <filename> <env...>
__read_generate_files() {
    local vault_filter="$1"
    local file_arg="$2"
    shift 2
    local fields=("$@")

    local extension="${file_arg##*.}"
    local name
    name=$(basename -s ".$extension" "$file_arg")
    mkdir -p "$path/$name"

    local field
    for field in "${fields[@]}"; do
        local out_file="$name.$field.$extension"

        local vault mapped_vault
        if mapped_vault=$(get_vault_for_file "$out_file"); then
            vault="$mapped_vault"
        else
            echo "[!] No vault mapping for $out_file, skipping"
            continue
        fi

        if [[ -n "$vault_filter" && "$vault" != "$vault_filter" ]]; then
            continue
        fi

        if ! can_access_vault "$vault"; then
            echo "[!] No access to '$vault', skipping $out_file"
            continue
        fi

        local doc_name="${out_file%.*}"
        op document get "$doc_name" --out-file "$path/$name/$out_file" --vault "$vault" --force
        echo "[+] $out_file (from $vault)"
    done
    return 0
}

__read() {
    local arg="${1:-}"
    if [[ "$arg" == "-h" || "$arg" == "--help" ]]; then
        __read_usage; return 0
    fi

    require_tools || exit 1
    setup_styles
    load_config || exit 1
    platform_validate "$platform" || exit 1

    mkdir -p "$path"

    local vault_filter=""
    if [[ -n "$arg" ]]; then
        if ! vault_filter=$(resolve_vault_filter "$arg"); then
            echo "Invalid vault argument: $arg"
            echo "Available: ${vaults[*]}"
            echo
            __read_usage
            exit 1
        fi
        echo "Filtering to vault: $vault_filter"
        echo
    fi

    detect_vault_access can_access_vault "read" "$vault_filter"
    echo

    echo "Fetching configurations..."
    echo

    if [[ "${#files[@]}" -eq 0 ]]; then
        echo "[!] No files configured (files=[] in $CONFIG_FILE_NAME)"
        exit 1
    fi

    local entry name envs_csv
    local -a envs
    for entry in "${files[@]}"; do
        name="${entry%:*}"
        envs_csv="${entry##*:}"
        if [[ "$envs_csv" == "*" ]]; then
            envs=("${environments[@]}")
        else
            IFS=',' read -r -a envs <<< "$envs_csv"
        fi
        __read_generate_files "$vault_filter" "$name" "${envs[@]}"
    done

    echo
    echo "Done!"
    return 0
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bats tests/read.bats`
Expected: 2 tests PASS.

- [ ] **Step 5: Manual smoke test of the wired command**

Run: `INFINUM_SECRETS_SOURCES=./sources ./infinum-secrets.sh read -h`
Expected: prints the read usage block, exits 0 (no `op`/config needed for `-h`).

- [ ] **Step 6: Commit**

```bash
git add sources/__read.sh tests/read.bats
git commit -m "feat: add read command (config-driven download)"
```

---

### Task 6: Write command (`__write.sh`)

**Files:**
- Create: `sources/__write.sh`
- Test: `tests/write.bats` (pure helper `match_environment`); interactive flow verified manually.

Ports `ios/.onepassword/write.sh`: `main` → `__write`, config from `load_config`, tools/styles explicit, platform gated.

- [ ] **Step 1: Write the failing test for `match_environment`**

```bash
# tests/write.bats
setup() {
    REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
    source "$REPO_ROOT/sources/__constants.sh"
    source "$REPO_ROOT/sources/helpers/__op_utils.sh"
    source "$REPO_ROOT/sources/__write.sh"
    environments=("production" "staging")
}

@test "match_environment finds staging in dotted name" {
    run match_environment "Keys.staging.swift"
    [ "$status" -eq 0 ]
    [ "$output" = "staging" ]
}

@test "match_environment finds production" {
    run match_environment "Config.production.json"
    [ "$output" = "production" ]
}

@test "match_environment returns non-zero when no env present" {
    run match_environment "Keys.swift"
    [ "$status" -ne 0 ]
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bats tests/write.bats`
Expected: FAIL — source error / `match_environment: command not found`.

- [ ] **Step 3: Write `sources/__write.sh`**

```bash
# sources/__write.sh
#!/usr/bin/env bash
# __write — uploads secret files from a local directory to 1Password.

__write_usage() {
    echo "Usage: $CLI_NAME write [-h] [directory]"
    echo
    echo "Uploads secret files from a local directory to 1Password."
    echo
    echo "Arguments:"
    echo "  directory   Optional. Name of the directory inside the configured path."
    echo "              If omitted, you will be prompted interactively."
    echo
    echo "Options:"
    echo "  -h          Show this help message and exit."
    return 0
}

# Returns the matching environment for a filename, anchored on dots, else non-zero.
match_environment() {
    local file_name="$1"
    local env
    for env in "${environments[@]}"; do
        if [[ ".$file_name." == *.${env}.* ]]; then
            echo "$env"
            return 0
        fi
    done
    return 1
}

__write() {
    local arg="${1:-}"
    if [[ "$arg" == "-h" || "$arg" == "--help" ]]; then
        __write_usage; return 0
    fi

    require_tools || exit 1
    setup_styles
    load_config || exit 1
    platform_validate "$platform" || exit 1

    clear
    echo
    echo "###############################################################"
    echo "                       SECRET WRITE SCRIPT                     "
    echo "###############################################################"
    echo

    echo "Before you proceed, make sure that you have the latest files locally."
    read -r -e -p "Have you pulled the files from 1Password? Press enter to continue, or 'q' to quit: " response
    [[ $response == q ]] && { echo "No problem! Come back again after you've updated the files."; exit; }

    echo
    echo "==============================================================="
    echo "To write the files, specify which directory contains those files"
    echo "It will create appropriate 1password structure based on that information"
    echo
    echo "${bold}NOTE:${normal} The directory itself must be placed inside '$path'"

    local dir="$arg"
    if [[ -n "$dir" ]]; then
        if [[ ! -d "$path/$dir" ]]; then
            echo "$path/$dir does not exist."
            exit 1
        fi
    else
        while read -r -e -p "Enter directory name: " dir && [[ ! -d "$path/$dir" ]]; do
            [[ $dir == q ]] && { echo "See you around."; exit; }
            echo
            echo "$path/$dir does not exist. To quit, enter 'q'."
        done
    fi

    echo
    local needed_vaults=()
    local file base_name mapped_vault
    for file in "$path/$dir"/*; do
        base_name=$(basename "$file")
        if mapped_vault=$(get_vault_for_file "$base_name"); then
            local already_added=false v
            for v in "${needed_vaults[@]+"${needed_vaults[@]}"}"; do
                [[ "$v" == "$mapped_vault" ]] && { already_added=true; break; }
            done
            [[ "$already_added" = false ]] && needed_vaults+=("$mapped_vault")
        else
            echo "[!] No vault mapping for $base_name, skipping"
        fi
    done

    if [[ "${#needed_vaults[@]}" -eq 0 ]]; then
        echo "No files with valid vault mappings found in '$dir'."
        exit 1
    fi

    local vault
    for vault in "${needed_vaults[@]}"; do
        detect_vault_access can_write_vault "write" "$vault"
    done

    echo
    local has_files=false
    for file in "$path/$dir"/*; do
        base_name=$(basename "$file")
        if ! mapped_vault=$(get_vault_for_file "$base_name"); then
            continue
        fi
        if can_write_vault "$mapped_vault"; then
            echo "[+] $base_name → $mapped_vault"
            has_files=true
        else
            echo "[!] $base_name → $mapped_vault (no write access, will skip)"
        fi
    done

    if [[ "$has_files" = false ]]; then
        echo
        echo "No files to upload (no vault access or no mappings)."
        exit 1
    fi

    echo
    read -r -e -p "Are those the files you want to upload? Press enter to continue, or 'q' to quit: " response
    [[ $response == q ]] && { echo "Okay, you can try again with different ones."; exit; }

    echo
    echo "Uploading..."
    echo

    local file_path doc_name
    for file_path in "$path/$dir"/*; do
        base_name=$(basename "$file_path")
        if ! mapped_vault=$(get_vault_for_file "$base_name"); then
            continue
        fi
        if ! can_write_vault "$mapped_vault"; then
            continue
        fi
        if ! match_environment "$base_name" > /dev/null; then
            echo
            echo "Validation failed for '$file_path'"
            echo "Name must contain one of the following environment descriptions: ${environments[*]}"
            echo "Those environments must be separated by dots, e.g. my_file.staging.json"
            exit 1
        fi
        doc_name="${base_name%.*}"
        if op item get "$doc_name" --vault "$mapped_vault" > /dev/null 2>&1; then
            op document edit "$doc_name" "$file_path" --vault "$mapped_vault"
        else
            op document create "$file_path" --title "$doc_name" --vault "$mapped_vault"
        fi
    done

    echo "Done!"
    return 0
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bats tests/write.bats`
Expected: 3 tests PASS.

- [ ] **Step 5: Manual smoke test**

Run: `INFINUM_SECRETS_SOURCES=./sources ./infinum-secrets.sh write -h`
Expected: prints write usage block, exits 0.

- [ ] **Step 6: Commit**

```bash
git add sources/__write.sh tests/write.bats
git commit -m "feat: add write command (config-driven upload)"
```

---

### Task 7: Help command (`__help.sh`)

**Files:**
- Create: `sources/__help.sh`
- Test: extend `tests/entry.bats`

- [ ] **Step 1: Add failing help assertions to `tests/entry.bats`**

Append these tests to `tests/entry.bats`:

```bash
@test "--help prints usage and lists commands" {
    run bash "$CLI" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage: infinum-secrets"* ]]
    [[ "$output" == *"read"* ]]
    [[ "$output" == *"write"* ]]
    [[ "$output" == *"init"* ]]
    [[ "$output" == *"doctor"* ]]
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bats tests/entry.bats`
Expected: the new test FAILs — `__help: command not found`.

- [ ] **Step 3: Write `sources/__help.sh`**

```bash
# sources/__help.sh
#!/usr/bin/env bash
# __help — top-level usage.

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
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bats tests/entry.bats`
Expected: all entry tests PASS (4 total).

- [ ] **Step 5: Commit**

```bash
git add sources/__help.sh tests/entry.bats
git commit -m "feat: add help command"
```

---

### Task 8: Init command + config template

**Files:**
- Create: `sources/secrets.config.json` (template)
- Create: `sources/__init.sh`
- Test: `tests/init.bats`

- [ ] **Step 1: Write the config template**

```json
{
  "platform": "ios",
  "path": "ProjectName/SupportingFiles/Vault",
  "environments": ["production", "staging"],
  "vaults": ["project-projectname-ios", "project-projectname-ios-staging"],
  "files": [
    { "name": "Keys.swift", "environments": ["*"] }
  ],
  "fileVaults": [
    { "pattern": "*.staging.*", "vault": "project-projectname-ios-staging" },
    { "pattern": "*.production.*", "vault": "project-projectname-ios" }
  ]
}
```

- [ ] **Step 2: Write the failing init test**

```bash
# tests/init.bats
setup() {
    REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
    export INFINUM_SECRETS_SOURCES="$REPO_ROOT/sources"
    CLI="$REPO_ROOT/infinum-secrets.sh"
    WORKDIR="$(mktemp -d)"
    cd "$WORKDIR"
}
teardown() {
    cd /
    rm -rf "$WORKDIR"
}

@test "init creates secrets.config.json with ios defaults" {
    run bash "$CLI" init
    [ "$status" -eq 0 ]
    [ -f "$WORKDIR/secrets.config.json" ]
    run jq -r '.platform' "$WORKDIR/secrets.config.json"
    [ "$output" = "ios" ]
}

@test "init --platform android sets platform and android path" {
    run bash "$CLI" init --platform android
    [ "$status" -eq 0 ]
    run jq -r '.platform' "$WORKDIR/secrets.config.json"
    [ "$output" = "android" ]
    run jq -r '.path' "$WORKDIR/secrets.config.json"
    [ "$output" = "app/src/main/secrets" ]
}

@test "init refuses to overwrite existing config without --force" {
    echo '{}' > "$WORKDIR/secrets.config.json"
    run bash "$CLI" init
    [ "$status" -ne 0 ]
    [[ "$output" == *"already exists"* ]]
}

@test "init --force overwrites existing config" {
    echo '{}' > "$WORKDIR/secrets.config.json"
    run bash "$CLI" init --force
    [ "$status" -eq 0 ]
    run jq -r '.platform' "$WORKDIR/secrets.config.json"
    [ "$output" = "ios" ]
}
```

- [ ] **Step 3: Run test to verify it fails**

Run: `bats tests/init.bats`
Expected: FAIL — `__init: command not found`.

- [ ] **Step 4: Write `sources/__init.sh`**

```bash
# sources/__init.sh
#!/usr/bin/env bash
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

    require_tools || return 1

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
```

- [ ] **Step 5: Run test to verify it passes**

Run: `bats tests/init.bats`
Expected: 4 tests PASS.

- [ ] **Step 6: Commit**

```bash
git add sources/secrets.config.json sources/__init.sh tests/init.bats
git commit -m "feat: add init command and config template"
```

---

### Task 9: Doctor command (`__doctor.sh`)

**Files:**
- Create: `sources/__doctor.sh`
- Test: `tests/doctor.bats` (config-validation path, no `op` required); vault-access table verified manually.

- [ ] **Step 1: Write the failing doctor test**

```bash
# tests/doctor.bats
setup() {
    REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
    export INFINUM_SECRETS_SOURCES="$REPO_ROOT/sources"
    CLI="$REPO_ROOT/infinum-secrets.sh"
    WORKDIR="$(mktemp -d)"
    cd "$WORKDIR"
}
teardown() {
    cd /
    rm -rf "$WORKDIR"
}

@test "doctor reports missing config" {
    run bash "$CLI" doctor
    [[ "$output" == *"secrets.config.json not found"* ]]
}

@test "doctor reports invalid config JSON" {
    echo "{ broken" > "$WORKDIR/secrets.config.json"
    run bash "$CLI" doctor
    [[ "$output" == *"valid JSON"* || "$output" == *"invalid"* ]]
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bats tests/doctor.bats`
Expected: FAIL — `__doctor: command not found`.

- [ ] **Step 3: Write `sources/__doctor.sh`**

```bash
# sources/__doctor.sh
#!/usr/bin/env bash
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
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bats tests/doctor.bats`
Expected: 2 tests PASS.

- [ ] **Step 5: Manual smoke test (with op signed in + a real config)**

Run from a project that has a valid `secrets.config.json`:
`INFINUM_SECRETS_SOURCES=/path/to/repo/sources /path/to/repo/infinum-secrets.sh doctor`
Expected: tooling ✓, session ✓, config ✓, and per-vault read/write table.

- [ ] **Step 6: Commit**

```bash
git add sources/__doctor.sh tests/doctor.bats
git commit -m "feat: add doctor diagnostics command"
```

---

### Task 10: Installer + self-update

**Files:**
- Create: `install.sh`
- Create: `sources/__auto_update.sh`

The installer is invoked by curl; `--update` re-runs the same flow. Both share the
copy logic. `install.sh` is standalone (runs before anything is installed), so it
does not source the library.

- [ ] **Step 1: Write `install.sh`**

```bash
# install.sh
#!/usr/bin/env bash

set -euo pipefail

REPO_URL="https://github.com/infinum/mobile-onepassword-secrets.git"
TMP_DIR=".infinum_secrets_tmp"
BIN_NAME="infinum-secrets"
SOURCES_NAME=".infinum-secrets-sources"

SILENT=false
[[ "${1:-}" == "--silent" ]] && SILENT=true

# Pick an install dir that is writable and on PATH.
choose_bindir() {
    local candidates=("/usr/local/bin" "$HOME/.local/bin")
    local dir
    for dir in "${candidates[@]}"; do
        if [[ -d "$dir" && -w "$dir" ]]; then
            echo "$dir"; return 0
        fi
    done
    # /usr/local/bin exists but not writable → signal sudo path.
    if [[ -d "/usr/local/bin" ]]; then
        echo "/usr/local/bin"; return 2
    fi
    mkdir -p "$HOME/.local/bin"
    echo "$HOME/.local/bin"; return 0
}

main() {
    local bindir rc use_sudo=""
    bindir=$(choose_bindir) || rc=$?
    rc=${rc:-0}
    if [[ "$rc" -eq 2 ]]; then
        echo "Note: $bindir is not writable; will use sudo."
        use_sudo="sudo"
    fi

    if [[ "$SILENT" != true ]]; then
        echo "This will install '$BIN_NAME' to $bindir."
        read -r -p "Do you want to proceed? [y/n] " answer
        [[ "$answer" == "y" ]] || { echo "Aborted."; exit 0; }
    fi

    trap 'rm -rf "$TMP_DIR"' EXIT
    rm -rf "$TMP_DIR"
    git clone --quiet "$REPO_URL" "$TMP_DIR"

    $use_sudo cp "$TMP_DIR/$BIN_NAME.sh" "$bindir/$BIN_NAME"
    $use_sudo chmod +rx "$bindir/$BIN_NAME"

    $use_sudo rm -rf "$bindir/$SOURCES_NAME"
    $use_sudo mkdir -p "$bindir/$SOURCES_NAME"
    $use_sudo cp -a "$TMP_DIR/sources/." "$bindir/$SOURCES_NAME/"
    $use_sudo chmod -R +rx "$bindir/$SOURCES_NAME"

    # The installed entry must default to the installed sources dir.
    $use_sudo sed -i.bak "s|/usr/local/bin/.infinum-secrets-sources|$bindir/$SOURCES_NAME|g" "$bindir/$BIN_NAME"
    $use_sudo rm -f "$bindir/$BIN_NAME.bak"

    echo
    echo "Installed: $bindir/$BIN_NAME"
    echo "Run '$BIN_NAME --help' to get started."
}

main "$@"
```

- [ ] **Step 2: Write `sources/__auto_update.sh`**

```bash
# sources/__auto_update.sh
#!/usr/bin/env bash
# __script_auto_update — re-run the installer to pull the latest version.

__script_auto_update() {
    echo "Updating $CLI_NAME to the latest version..."
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/infinum/mobile-onepassword-secrets/main/install.sh)" -- --silent
}
```

- [ ] **Step 3: Lint both scripts**

Run: `shellcheck install.sh sources/__auto_update.sh infinum-secrets.sh sources/*.sh sources/helpers/*.sh`
Expected: no errors. (Warnings already suppressed inline where intentional, e.g. SC2034, SC2053, SC1090.)

- [ ] **Step 4: Dry-run the installer logic locally (no real install)**

Run: `bash -n install.sh`
Expected: no syntax errors. (Full install is verified manually in Task 12.)

- [ ] **Step 5: Commit**

```bash
git add install.sh sources/__auto_update.sh
git commit -m "feat: add curl installer and self-update"
```

---

### Task 11: Remove legacy iOS scripts

**Files:**
- Delete: `ios/.onepassword/config.sh`, `ios/.onepassword/utils.sh`, `ios/.onepassword/read.sh`, `ios/.onepassword/write.sh`

All logic now lives in `sources/`. Removing the standalone copies prevents drift.

- [ ] **Step 1: Confirm nothing else references the old paths**

Run: `grep -rn "\.onepassword" --include="*.sh" --include="*.md" . || echo "no refs"`
Expected: only the design spec / plan mention them historically; no live source references the `ios/.onepassword/*.sh` files.

- [ ] **Step 2: Remove the legacy scripts**

Run:
```bash
git rm ios/.onepassword/config.sh ios/.onepassword/utils.sh ios/.onepassword/read.sh ios/.onepassword/write.sh
```

- [ ] **Step 3: Run the full test suite**

Run: `bats tests/`
Expected: all tests across all `.bats` files PASS.

- [ ] **Step 4: Commit**

```bash
git commit -m "refactor: remove legacy ios/.onepassword scripts (superseded by CLI)"
```

---

### Task 12: README + end-to-end manual verification

**Files:**
- Create: `README.md`

- [ ] **Step 1: Write `README.md`**

````markdown
# infinum-secrets

CLI to sync project secrets between a local directory and 1Password vaults,
driven by a per-project `secrets.config.json`. iOS is supported today; Android
is scaffolded.

## Requirements

- [`op`](https://developer.1password.com/docs/cli/get-started/) — 1Password CLI:
  `brew install --cask 1password-cli`
- `jq`: `brew install jq`

## Install

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/infinum/mobile-onepassword-secrets/main/install.sh)"
```

Update later with `infinum-secrets --update`.

## Usage

```bash
infinum-secrets init --platform ios   # scaffold secrets.config.json
infinum-secrets doctor                # check tooling, sign-in, vault access
infinum-secrets read                  # download secrets into the configured path
infinum-secrets read <vault>          # only from one vault
infinum-secrets write <dir>           # upload a local dir's secrets
```

## Configuration (`secrets.config.json`)

| Field | Type | Meaning |
|-------|------|---------|
| `platform` | string | `ios` or `android`. |
| `path` | string | Local dir where secret files live. |
| `environments` | string[] | Known envs; drives filename validation and `*` expansion. |
| `vaults` | string[] | 1Password vaults for this project. |
| `files` | object[] | `{ name, environments }`; `environments: ["*"]` = all. |
| `fileVaults` | object[] | `{ pattern, vault }`; first glob match wins. |

Files are named `<base>.<env>.<ext>` (e.g. `Keys.production.swift`).

## Development

Run from the repo without installing:

```bash
INFINUM_SECRETS_SOURCES=./sources ./infinum-secrets.sh --help
```

Run tests (requires `bats-core`: `brew install bats-core`):

```bash
bats tests/
```
````

- [ ] **Step 2: Full local end-to-end (manual, requires op signed in)**

```bash
# in a scratch dir
INFINUM_SECRETS_SOURCES="$PWD/sources" "$PWD/infinum-secrets.sh" init --platform ios
# edit secrets.config.json: set real vaults/files/path
INFINUM_SECRETS_SOURCES="$PWD/sources" "$PWD/infinum-secrets.sh" doctor
INFINUM_SECRETS_SOURCES="$PWD/sources" "$PWD/infinum-secrets.sh" read
```
Expected: init creates config; doctor shows all ✓ and the access table; read downloads files into the configured path.

- [ ] **Step 3: Real install smoke test**

Run the curl install command (or `bash install.sh` from a clone), then in a project dir:
```bash
infinum-secrets --version
infinum-secrets doctor
```
Expected: prints version; doctor runs using the installed sources dir (no `INFINUM_SECRETS_SOURCES` needed).

- [ ] **Step 4: Commit**

```bash
git add README.md
git commit -m "docs: add README with install, usage, and config reference"
```

---

## Self-Review Notes

- **Spec coverage:** repo layout (Tasks 1–10), installer (10), entry dispatch (1), JSON config + parser (2), shared logic + platform hook (4, gated in 5/6), commands init/read/write/doctor (5,6,8,9), `--version`/`--update`/`--help` (1,7,10), deps + error handling (3,9), versioning constant (1), migration/removal of legacy scripts (11), testing (bats throughout), README (12). All spec sections map to a task.
- **Bash 3.2:** parser and all array builds use `while read` loops, not `mapfile`.
- **Type/name consistency:** `load_config`, `find_config`, `get_vault_for_file`, `resolve_vault_filter`, `match_environment`, `platform_default_path`, `platform_validate`, `require_tools`, `setup_styles`, `print_vault_access`, `detect_vault_access`, `__read`/`__write`/`__init`/`__doctor`/`__help`/`__script_auto_update` are used consistently across entry, commands, and tests. Config arrays (`environments`, `vaults`, `files`, `file_vaults`) and scalars (`platform`, `path`) match between parser (Task 2) and consumers (Tasks 5/6/9).
- **op-dependent gaps:** functions calling `op` aren't unit-tested (no `op` in CI); they're isolated as small functions and covered by manual smoke steps (Tasks 5,6,9,12).
```
