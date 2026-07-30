# tests/op_utils.bats
setup() {
    REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
    source "$REPO_ROOT/sources/__constants.sh"
    source "$REPO_ROOT/sources/helpers/__op_utils.sh"
    vault_aliases=(
        "staging:project-x-staging"
        "project-x-staging:project-x-staging"
        "production:project-x"
        "project-x:project-x"
    )
}

@test "to_lower lowercases" {
    run to_lower "ABC-Def"
    [ "$output" = "abc-def" ]
}

@test "doc_title_for is the basename with extension" {
    run doc_title_for "Keys/Keys.staging.swift"
    [ "$output" = "Keys.staging.swift" ]
    run doc_title_for "secrets.properties"
    [ "$output" = "secrets.properties" ]
}

@test "resolve_vault_filter resolves a friendly label (case-insensitive)" {
    run resolve_vault_filter "STAGING"
    [ "$status" -eq 0 ]
    [ "$output" = "project-x-staging" ]
}

@test "resolve_vault_filter resolves a full vault name" {
    run resolve_vault_filter "project-x"
    [ "$status" -eq 0 ]
    [ "$output" = "project-x" ]
}

@test "resolve_vault_filter returns non-zero for an unknown value" {
    run resolve_vault_filter "nope"
    [ "$status" -ne 0 ]
}

@test "is_service_account reflects the token env var" {
    OP_SERVICE_ACCOUNT_TOKEN="" run is_service_account
    [ "$status" -ne 0 ]
    OP_SERVICE_ACCOUNT_TOKEN="ops_abc" run is_service_account
    [ "$status" -eq 0 ]
}

@test "op_bounded kills an overrunning command and returns 124" {
    run op_bounded 1 sleep 10
    [ "$status" -eq 124 ]
}

@test "op_bounded returns the command's own status when it finishes in time" {
    run op_bounded 5 true
    [ "$status" -eq 0 ]
    run op_bounded 5 false
    [ "$status" -ne 0 ]
    [ "$status" -ne 124 ]
}
