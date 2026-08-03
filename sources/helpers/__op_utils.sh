#!/usr/bin/env bash
# sources/helpers/__op_utils.sh
# shellcheck disable=SC2034,SC2154
# SC2034: color/cache vars set here are consumed by sourcing scripts.
# SC2154: file_vaults and vaults are injected at runtime by the config parser or tests.
# Helper functions for 1Password interaction. Sourcing is side-effect-free;
# call require_tools / setup_styles explicitly.

# How to install each external CLI we depend on, and what to call it in
# output. Single source of truth: require_tools fails fast on the first
# missing tool, doctor reports every tool and tallies, but neither spells
# out an install command of its own.
tool_install_hint() {
    case "$1" in
        op) printf '%s' "brew install --cask 1password-cli" ;;
        jq) printf '%s' "brew install jq" ;;
        *)  printf '%s' "brew install $1" ;;
    esac
}

# Human-readable name for a tool, empty when the command name says it all.
tool_label() {
    case "$1" in
        op) printf '%s' "1Password CLI" ;;
    esac
}

# Verifies required CLIs are installed. Call before any op-dependent command.
require_tools() {
    local t
    for t in op jq; do
        command -v "$t" >/dev/null 2>&1 && continue
        echo "Error: '$t' is required but not installed." >&2
        echo "Install with: $(tool_install_hint "$t")" >&2
        return 1
    done
    return 0
}

# Prints doctor's one-line verdict for a single tool and returns non-zero
# when it is missing, so the caller can count the failure. Needs
# setup_styles to have run.
report_tool() {
    local t="$1" label
    local ok="${green}✓${reset}" bad="${red}✗${reset}"
    label="$(tool_label "$t")"
    if [[ -n "$label" ]]; then
        label=" ($label)"
    fi
    if command -v "$t" >/dev/null 2>&1; then
        echo "  $ok $t$label installed"
        return 0
    fi
    echo "  $bad $t not installed — $(tool_install_hint "$t")"
    return 1
}

# Runs a command with a hard timeout, killing it (SIGKILL) if it overruns.
# stdin is taken from /dev/null so a hidden prompt can't block. Output discarded.
# `op` ignores soft signals while waiting on the desktop-app integration, so we
# poll and SIGKILL — a soft timeout is not enough.
# Usage: op_bounded <seconds> <command> [args...]  → command status, or 124 on timeout.
op_bounded() {
    local secs="$1"; shift
    local pid waited=0 rc=0
    "$@" </dev/null >/dev/null 2>&1 &
    pid=$!
    while kill -0 "$pid" 2>/dev/null; do
        if [[ "$waited" -ge "$secs" ]]; then
            kill -9 "$pid" 2>/dev/null
            wait "$pid" 2>/dev/null || true
            return 124
        fi
        sleep 1
        waited=$((waited + 1))
    done
    if wait "$pid"; then rc=0; else rc=$?; fi
    return "$rc"
}

# Returns 0 if there is a usable 1Password session (bounded, non-interactive).
# `op whoami` works for both personal sign-ins and service-account tokens
# (unlike `op user get --me`, which fails for service accounts).
# Returns 124 if op did not respond in time, or op's error status otherwise.
op_signed_in() {
    op_bounded "${1:-10}" op whoami
}

# Ensures a usable op session before any vault access checks. The first op
# call triggers the desktop-app sign-in prompt and blocks until it resolves
# (service accounts answer instantly), so this must run before the access
# matrix — a still-pending sign-in would otherwise read as "no access" (✗)
# for whichever vault happens to be checked first. Interactive by design:
# unlike op_signed_in (doctor's bounded, non-interactive probe), this call
# is meant to wait for the user. Prints a hint and fails if no session
# could be established.
ensure_op_session() {
    if op whoami >/dev/null 2>&1; then
        return 0
    fi
    # `op whoami` only reports an already-established session — it does not
    # itself trigger the desktop-app authorization, so with the app
    # integration it can fail while real commands authorize fine. Establish
    # the session with a real read-only call (may prompt and wait).
    if op vault list >/dev/null 2>&1; then
        return 0
    fi
    echo "Error: not signed in to 1Password. Unlock the 1Password app (or run 'op signin'), then retry." >&2
    return 1
}

# True if a 1Password service-account token is configured. `op` uses it
# automatically (CI-friendly, no desktop app). Service accounts have no user
# identity, so user-based permission checks don't apply to them.
is_service_account() {
    [[ -n "${OP_SERVICE_ACCOUNT_TOKEN:-}" ]]
}

# Colors / styles. Gracefully degrade with no terminal (e.g. CI).
# shellcheck disable=SC2034
setup_styles() {
    green=$(tput setaf 2 2>/dev/null || true)
    red=$(tput setaf 1 2>/dev/null || true)
    bold=$(tput bold 2>/dev/null || true)
    reset=$(tput sgr0 2>/dev/null || true)
}

# Lowercase a string portably (bash 3.2 has no ${var,,}).
to_lower() {
    printf '%s' "$1" | tr '[:upper:]' '[:lower:]'
}

# The 1Password document title for a file path: its base name (with extension).
# e.g. Keys/Keys.staging.swift -> Keys.staging.swift
doc_title_for() {
    echo "${1##*/}"
}

# Resolves a CLI arg (a vault name or friendly label) to the 1Password vault
# name, using the vault_aliases map. Case-insensitive.
resolve_vault_filter() {
    local arg_lc key vault entry
    arg_lc=$(to_lower "$1")
    for entry in "${vault_aliases[@]+"${vault_aliases[@]}"}"; do
        key="${entry%:*}"
        vault="${entry##*:}"
        if [[ "$(to_lower "$key")" == "$arg_lc" ]]; then
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
    # Service accounts have no user identity to introspect; assume writable and
    # let `op` enforce on the actual write (they are read-only unless granted).
    if is_service_account; then
        return 0
    fi
    local user_id
    user_id=$(_get_current_user_id)
    if [[ -z "$user_id" ]]; then
        return 1
    fi
    op vault user list "$vault_name" --format=json 2>/dev/null \
        | jq -e --arg uid "$user_id" '.[] | select(.id == $uid) | .permissions | index("allow_editing")' \
        > /dev/null 2>&1
}

# --- Path-field item resolution ---------------------------------------------
# The document title is the file's base name, so two files sharing a name but
# living in different folders need more than the title to tell apart. write
# stamps each item with a custom text field 'path' holding the repo-relative
# path; resolution matches on it, and read/write then operate by item ID.

# Per-vault cache of full item JSON (bash 3.2: no assoc arrays, so parallel
# indexed arrays). Command substitution runs in a subshell, where cache writes
# are lost — callers that loop should warm the cache once per vault with a
# direct `get_vault_items <vault> >/dev/null` first.
_vault_items_names=()
_vault_items_json=()

# Echoes a JSON array of full items (id, title, fields) for a vault; cached.
# Always returns 0; op failures and empty vaults yield [].
get_vault_items() {
    local vault="$1" i list
    for i in ${_vault_items_names[@]+"${!_vault_items_names[@]}"}; do
        if [[ "${_vault_items_names[$i]}" == "$vault" ]]; then
            printf '%s\n' "${_vault_items_json[$i]}"
            return 0
        fi
    done
    if ! list=$(op item list --vault "$vault" --format json 2>/dev/null); then
        list="[]"
    fi
    if [[ -z "$list" ]] || printf '%s' "$list" | jq -e 'length == 0' >/dev/null 2>&1; then
        list="[]"
    else
        # One batched fetch for the whole vault: pipe the summaries into
        # `op item get -`, which emits a stream of full items; slurp to an array.
        if ! list=$(printf '%s' "$list" | op item get - --format json 2>/dev/null | jq -s '.'); then
            list="[]"
        fi
    fi
    _vault_items_names+=("$vault")
    _vault_items_json+=("$list")
    printf '%s\n' "$list"
    return 0
}

# Resolves the 1Password item for a repo-relative path within a vault.
# Always returns 0 (pipefail-friendly); echoes a verdict:
#   "found <id>"  exactly one title candidate whose 'path' field matches
#   "adopt <id>"  no path match, but a single candidate with no 'path' field
#   "none"        nothing to reuse (write should create; read reports missing)
#   "ambiguous"   duplicate stamps, or several candidates incl. unstamped ones
# The optional claimed-ids csv excludes items already matched this run, so two
# entries sharing a base name can't adopt the same unstamped item.
# Usage: resolve_item_for_path <vault> <relpath> [claimed_ids_csv]
resolve_item_for_path() {
    local vault="$1" rel="$2" claimed="${3:-}" title items
    title=$(doc_title_for "$rel")
    items=$(get_vault_items "$vault")
    printf '%s' "$items" | jq -r --arg t "$title" --arg p "$rel" --arg cl "$claimed" '
        ($cl | split(",")) as $claimed
        | [ .[] | select(.title == $t) | select([.id] | inside($claimed) | not) ] as $cand
        | [ $cand[] | select((.fields // []) | any(.label == "path" and .value == $p)) ] as $exact
        | [ $cand[] | select((.fields // []) | any(.label == "path") | not) ] as $unstamped
        | if   ($exact | length) == 1 then "found \($exact[0].id)"
          elif ($exact | length) >  1 then "ambiguous"
          elif ($cand  | length) == 0 then "none"
          elif ($unstamped | length) == 0 then "none"
          elif ($cand | length) == 1 then "adopt \($cand[0].id)"
          else "ambiguous"
          end'
    return 0
}

# Stamps the repo-relative path onto an item as the 'path' text field
# (creates the field or updates it in place).
# Usage: stamp_item_path <item_id> <relpath> <vault>
stamp_item_path() {
    op item edit "$1" "path[text]=$2" --vault "$3" >/dev/null 2>&1
}

# Prints each vault with a green check or red cross per the given check function.
print_vault_access() {
    local check_fn="$1"  # can_access_vault or can_write_vault
    local vault
    for vault in "${vaults[@]+"${vaults[@]}"}"; do
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
        for vault in "${vaults[@]+"${vaults[@]}"}"; do
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
