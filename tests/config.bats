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
