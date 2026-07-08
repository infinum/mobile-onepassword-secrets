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

@test "init creates secrets.config.json with ios defaults" {
    run bash "$CLI" init
    [ "$status" -eq 0 ]
    [ -f "$WORKDIR/secrets.config.json" ]
    run jq -r '.platform' "$WORKDIR/secrets.config.json"
    [ "$output" = "ios" ]
}

@test "init --platform android sets platform and android path" {
    run bash "$CLI" init --platform android
    [ "$status" -eq 0 ]
    run jq -r '.platform' "$WORKDIR/secrets.config.json"
    [ "$output" = "android" ]
    run jq -r '.path' "$WORKDIR/secrets.config.json"
    [ "$output" = "app/src/main/secrets" ]
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
    run jq -r '.platform' "$WORKDIR/secrets.config.json"
    [ "$output" = "ios" ]
}
