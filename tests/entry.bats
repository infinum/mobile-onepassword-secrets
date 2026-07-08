setup() {
    REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
    export INFINUM_SECRETS_SOURCES="$REPO_ROOT/sources"
    CLI="$REPO_ROOT/infinum-secrets.sh"
}

@test "--version prints name and version" {
    run bash "$CLI" --version
    [ "$status" -eq 0 ]
    [[ "$output" == "infinum-secrets "* ]]
}

@test "unsupported command exits non-zero" {
    run bash "$CLI" frobnicate
    [ "$status" -ne 0 ]
    [[ "$output" == *"Unsupported command: frobnicate"* ]]
}

@test "no command exits non-zero" {
    run bash "$CLI"
    [ "$status" -ne 0 ]
    [[ "$output" == *"No command given"* ]]
}

@test "--help prints usage and lists commands" {
    run bash "$CLI" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage: infinum-secrets"* ]]
    [[ "$output" == *"read"* ]]
    [[ "$output" == *"write"* ]]
    [[ "$output" == *"init"* ]]
    [[ "$output" == *"doctor"* ]]
}
