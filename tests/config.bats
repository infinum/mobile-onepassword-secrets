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

@test "load_config derives vault names in order" {
    load_config "$FIXTURE"
    [ "${#vaults[@]}" -eq 2 ]
    [ "${vaults[0]}" = "project-projectname-ios-staging" ]
    [ "${vaults[1]}" = "project-projectname-ios" ]
}

@test "load_config flattens vault patterns to pattern:vault, order preserved" {
    load_config "$FIXTURE"
    [ "${#file_vaults[@]}" -eq 3 ]
    [ "${file_vaults[0]}" = "*.staging.*:project-projectname-ios-staging" ]
    [ "${file_vaults[1]}" = "*.dev.*:project-projectname-ios-staging" ]
    [ "${file_vaults[2]}" = "*.production.*:project-projectname-ios" ]
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
    echo '{"platform":"ios","path":"x"}' > "$tmp"
    run load_config "$tmp"
    rm -f "$tmp"
    [ "$status" -ne 0 ]
    [[ "$output" == *"missing required key"* ]]
}

@test "load_config fails when a vault has no patterns" {
    tmp="$(mktemp)"
    echo '{"platform":"ios","path":"x","vaults":[{"name":"v","patterns":[]}]}' > "$tmp"
    run load_config "$tmp"
    rm -f "$tmp"
    [ "$status" -ne 0 ]
    [[ "$output" == *"non-empty"* ]]
}

@test "load_config fails when a vault has no name" {
    tmp="$(mktemp)"
    echo '{"platform":"ios","path":"x","vaults":[{"patterns":["*.x.*"]}]}' > "$tmp"
    run load_config "$tmp"
    rm -f "$tmp"
    [ "$status" -ne 0 ]
    [[ "$output" == *"non-empty"* ]]
}
