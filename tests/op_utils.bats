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
