# tests/empty_arrays.bats
setup() {
    REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
    source "$REPO_ROOT/sources/__constants.sh"
    source "$REPO_ROOT/sources/helpers/__op_utils.sh"
    source "$REPO_ROOT/sources/__read.sh"
    source "$REPO_ROOT/sources/__write.sh"
}

@test "get_vault_for_file does not crash with empty file_vaults under set -u" {
    set -u
    file_vaults=()
    run get_vault_for_file "Keys.swift"
    [ "$status" -ne 0 ]   # no match → non-zero, but must not be an 'unbound variable' abort
    [[ "$output" != *"unbound"* ]]
}

@test "resolve_vault_filter does not crash with empty vaults under set -u" {
    set -u
    vaults=()
    run resolve_vault_filter "anything"
    [ "$status" -ne 0 ]
    [[ "$output" != *"unbound"* ]]
}

@test "vault_matches_file does not crash with empty file_vaults under set -u" {
    set -u
    file_vaults=()
    run vault_matches_file "v-any" "Keys.staging.swift"
    [ "$status" -ne 0 ]
    [[ "$output" != *"unbound"* ]]
}

@test "print_vault_access does not crash with empty vaults under set -u" {
    set -u
    vaults=()
    # stub the check fn so no op call happens
    can_access_vault() { return 0; }
    run print_vault_access can_access_vault
    [ "$status" -eq 0 ]
    [[ "$output" != *"unbound"* ]]
}
