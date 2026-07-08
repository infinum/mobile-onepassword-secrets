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
