# tests/doctor.bats
setup() {
    REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
    export INFINUM_SECRETS_SOURCES="$REPO_ROOT/sources"
    CLI="$REPO_ROOT/infinum-secrets.sh"
    WORKDIR="$(mktemp -d)"
    cd "$WORKDIR"
}
teardown() {
    cd /
    rm -rf "$WORKDIR"
}

@test "doctor reports missing config" {
    run bash "$CLI" doctor
    [[ "$output" == *"secrets.config.json not found"* ]]
}

@test "doctor reports invalid config JSON" {
    echo "{ broken" > "$WORKDIR/secrets.config.json"
    run bash "$CLI" doctor
    [[ "$output" == *"valid JSON"* || "$output" == *"invalid"* ]]
}
