# tests/empty_arrays.bats
# Guards against the bash 3.2 `set -u` unbound-array trap: expanding an empty
# array as "${arr[@]}" aborts unless guarded with "${arr[@]+...}".
setup() {
    REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
    source "$REPO_ROOT/sources/__constants.sh"
    source "$REPO_ROOT/sources/helpers/__op_utils.sh"
}

@test "resolve_vault_filter does not crash with empty vault_aliases under set -u" {
    set -u
    vault_aliases=()
    run resolve_vault_filter "anything"
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
