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
