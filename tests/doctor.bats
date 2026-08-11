# tests/doctor.bats
setup() {
    REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
    export INFINUM_SECRETS_SOURCES="$REPO_ROOT/sources"
    CLI="$REPO_ROOT/infinum-secrets.sh"
    WORKDIR="$(mktemp -d)"

    # Fast op shim so the session probe is deterministic and never touches the
    # real 1Password (which can block on the desktop-app integration).
    mkdir -p "$WORKDIR/bin"
    cat > "$WORKDIR/bin/op" <<'SHIM'
#!/usr/bin/env bash
if [ "$1" = whoami ]; then echo '{"user_uuid":"u1"}'; fi
exit 0
SHIM
    chmod +x "$WORKDIR/bin/op"
    export PATH="$WORKDIR/bin:$PATH"

    cd "$WORKDIR"
}
teardown() {
    cd /
    rm -rf "$WORKDIR"
}

@test "doctor reports missing config" {
    run bash "$CLI" doctor
    [[ "$output" == *".secrets.config.json not found"* ]]
}

@test "doctor reports invalid config JSON" {
    echo "{ broken" > "$WORKDIR/.secrets.config.json"
    run bash "$CLI" doctor
    [[ "$output" == *"valid JSON"* || "$output" == *"invalid"* ]]
}

@test "doctor detects a session via the app integration when whoami fails" {
    # `op whoami` only reports an established session; with the desktop-app
    # integration it can fail while real commands (vault list) authorize fine.
    cat > "$WORKDIR/bin/op" <<'SHIM'
#!/usr/bin/env bash
if [ "$1" = whoami ]; then exit 1; fi
if [ "$1" = vault ] && [ "$2" = list ]; then echo '[{"name":"v1"}]'; fi
exit 0
SHIM
    chmod +x "$WORKDIR/bin/op"
    run bash "$CLI" doctor
    [[ "$output" == *"signed in (via 1Password app integration)"* ]]
    [[ "$output" != *"not signed in"* ]]
}

@test "doctor reports not signed in when whoami and vault list both fail" {
    cat > "$WORKDIR/bin/op" <<'SHIM'
#!/usr/bin/env bash
if [ "$1" = whoami ]; then exit 1; fi
if [ "$1" = vault ] && [ "$2" = list ]; then exit 1; fi
exit 0
SHIM
    chmod +x "$WORKDIR/bin/op"
    run bash "$CLI" doctor
    [[ "$output" == *"not signed in"* ]]
}

@test "doctor does not hang when op is unresponsive (bounded probe)" {
    # An op that hangs forever must not hang doctor: the bounded probe kills it.
    cat > "$WORKDIR/bin/op" <<'SHIM'
#!/usr/bin/env bash
# exec so the killed pid IS the sleep (no orphaned grandchild left behind).
if [ "$1" = whoami ]; then exec sleep 300; fi
exit 0
SHIM
    chmod +x "$WORKDIR/bin/op"
    run bash "$CLI" doctor
    [[ "$output" == *"did not respond"* ]]
}
