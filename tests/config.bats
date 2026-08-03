# tests/config.bats
setup() {
    REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
    source "$REPO_ROOT/sources/__constants.sh"
    source "$REPO_ROOT/sources/helpers/__path_utils.sh"
    source "$REPO_ROOT/sources/helpers/__config.sh"
    FIXTURE="$REPO_ROOT/tests/fixtures/valid.config.json"
}

@test "load_config derives vault names in order" {
    load_config "$FIXTURE"
    [ "${#vaults[@]}" -eq 2 ]
    [ "${vaults[0]}" = "project-projectname-ios-staging" ]
    [ "${vaults[1]}" = "project-projectname-ios" ]
}

@test "load_config flattens files to relpath:vault, order preserved" {
    load_config "$FIXTURE"
    [ "${#file_vaults[@]}" -eq 3 ]
    [ "${file_vaults[0]}" = "Keys/Keys.staging.swift:project-projectname-ios-staging" ]
    [ "${file_vaults[1]}" = "Config/Config.dev.json:project-projectname-ios-staging" ]
    [ "${file_vaults[2]}" = "Keys/Keys.production.swift:project-projectname-ios" ]
}

@test "load_config builds aliases for label and vault name" {
    load_config "$FIXTURE"
    # label -> vault, and vault -> vault, for each entry
    printf '%s\n' "${vault_aliases[@]}" | grep -qx "staging:project-projectname-ios-staging"
    printf '%s\n' "${vault_aliases[@]}" | grep -qx "project-projectname-ios-staging:project-projectname-ios-staging"
    printf '%s\n' "${vault_aliases[@]}" | grep -qx "production:project-projectname-ios"
}

@test "load_config fails on invalid JSON" {
    tmp="$(mktemp)"
    echo "{ not json" > "$tmp"
    run load_config "$tmp"
    rm -f "$tmp"
    [ "$status" -ne 0 ]
    [[ "$output" == *"not valid JSON"* ]]
}

@test "load_config fails when 'vaults' is missing" {
    tmp="$(mktemp)"
    echo '{}' > "$tmp"
    run load_config "$tmp"
    rm -f "$tmp"
    [ "$status" -ne 0 ]
    [[ "$output" == *"missing required key 'vaults'"* ]]
}

@test "load_config fails when a vault has no files" {
    tmp="$(mktemp)"
    echo '{"vaults":[{"vault":"v","files":[]}]}' > "$tmp"
    run load_config "$tmp"
    rm -f "$tmp"
    [ "$status" -ne 0 ]
    [[ "$output" == *"non-empty"* ]]
}

@test "load_config fails when a vault has no vault name" {
    tmp="$(mktemp)"
    echo '{"vaults":[{"files":["a.txt"]}]}' > "$tmp"
    run load_config "$tmp"
    rm -f "$tmp"
    [ "$status" -ne 0 ]
    [[ "$output" == *"non-empty"* ]]
}

@test "load_config rejects absolute file paths" {
    tmp="$(mktemp)"
    echo '{"vaults":[{"vault":"v","files":["/etc/passwd"]}]}' > "$tmp"
    run load_config "$tmp"
    rm -f "$tmp"
    [ "$status" -ne 0 ]
    [[ "$output" == *"repo-relative"* ]]
}

@test "load_config rejects paths with .. components" {
    tmp="$(mktemp)"
    echo '{"vaults":[{"vault":"v","files":["a/../b.txt"]}]}' > "$tmp"
    run load_config "$tmp"
    rm -f "$tmp"
    [ "$status" -ne 0 ]
    [[ "$output" == *"repo-relative"* ]]
}

@test "load_config rejects home-relative paths" {
    tmp="$(mktemp)"
    echo '{"vaults":[{"vault":"v","files":["~/x.txt"]}]}' > "$tmp"
    run load_config "$tmp"
    rm -f "$tmp"
    [ "$status" -ne 0 ]
    [[ "$output" == *"repo-relative"* ]]
}

@test "load_config rejects paths containing a colon" {
    tmp="$(mktemp)"
    echo '{"vaults":[{"vault":"v","files":["a:b.txt"]}]}' > "$tmp"
    run load_config "$tmp"
    rm -f "$tmp"
    [ "$status" -ne 0 ]
    [[ "$output" == *"repo-relative"* ]]
}

@test "load_config splits glob entries into pattern_vaults" {
    tmp="$(mktemp)"
    echo '{"vaults":[{"vault":"v","files":["Keys/K.swift","Vault/**/*.plist","Certs/"]}]}' > "$tmp"
    load_config "$tmp"
    rm -f "$tmp"
    [ "${#file_vaults[@]}" -eq 1 ]
    [ "${file_vaults[0]}" = "Keys/K.swift:v" ]
    [ "${#pattern_vaults[@]}" -eq 2 ]
    [ "${pattern_vaults[0]}" = "Vault/**/*.plist:v" ]
    [ "${pattern_vaults[1]}" = "Certs/:v" ]
}

@test "load_config leaves pattern_vaults empty for literal-only configs" {
    load_config "$FIXTURE"
    [ "${#pattern_vaults[@]}" -eq 0 ]
    [ "${#file_vaults[@]}" -eq 3 ]
}

@test "load_config rejects traversal inside glob entries" {
    tmp="$(mktemp)"
    echo '{"vaults":[{"vault":"v","files":["Vault/../**"]}]}' > "$tmp"
    run load_config "$tmp"
    rm -f "$tmp"
    [ "$status" -ne 0 ]
    [[ "$output" == *"repo-relative"* ]]
}

@test "load_config accepts dotted names that are not traversals" {
    tmp="$(mktemp)"
    echo '{"vaults":[{"vault":"v","files":["a..b/c.txt", ".env.staging"]}]}' > "$tmp"
    run load_config "$tmp"
    rm -f "$tmp"
    [ "$status" -eq 0 ]
}
