# tests/op_utils.bats
setup() {
    REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
    source "$REPO_ROOT/sources/__constants.sh"
    source "$REPO_ROOT/sources/helpers/__op_utils.sh"
    file_vaults=(
        "*.staging.*:vault-staging"
        "*.dev.*:vault-staging"
        "*/production/*.swift:vault-prod"
    )
}

@test "get_vault_for_file matches staging pattern" {
    run get_vault_for_file "Keys.staging.swift"
    [ "$status" -eq 0 ]
    [ "$output" = "vault-staging" ]
}

@test "get_vault_for_file matches a second pattern of the same vault" {
    run get_vault_for_file "Keys.dev.swift"
    [ "$status" -eq 0 ]
    [ "$output" = "vault-staging" ]
}

@test "get_vault_for_file matches a relative-path pattern" {
    run get_vault_for_file "Config/production/Keys.swift"
    [ "$status" -eq 0 ]
    [ "$output" = "vault-prod" ]
}

@test "get_vault_for_file returns non-zero when no match" {
    run get_vault_for_file "Keys.swift"
    [ "$status" -ne 0 ]
}

@test "vault_matches_file is true only for that vault's patterns" {
    run vault_matches_file "vault-staging" "Keys.staging.swift"
    [ "$status" -eq 0 ]
    run vault_matches_file "vault-prod" "Keys.staging.swift"
    [ "$status" -ne 0 ]
}

@test "vault_matches_file honors relative-path patterns" {
    run vault_matches_file "vault-prod" "Config/production/Keys.swift"
    [ "$status" -eq 0 ]
}

@test "to_lower lowercases" {
    run to_lower "ABC-Def"
    [ "$output" = "abc-def" ]
}
