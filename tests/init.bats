# tests/init.bats
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

@test "init creates a valid secrets.config.json" {
    run bash "$CLI" init
    [ "$status" -eq 0 ]
    [ -f "$WORKDIR/secrets.config.json" ]
    run jq -e '.vaults | type == "array" and length > 0' "$WORKDIR/secrets.config.json"
    [ "$status" -eq 0 ]
}

@test "init refuses to overwrite existing config without --force" {
    echo '{}' > "$WORKDIR/secrets.config.json"
    run bash "$CLI" init
    [ "$status" -ne 0 ]
    [[ "$output" == *"already exists"* ]]
}

@test "init --force overwrites existing config" {
    echo '{}' > "$WORKDIR/secrets.config.json"
    run bash "$CLI" init --force
    [ "$status" -eq 0 ]
    run jq -e 'has("vaults")' "$WORKDIR/secrets.config.json"
    [ "$status" -eq 0 ]
}
