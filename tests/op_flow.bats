# tests/op_flow.bats
# Exercises read/write end-to-end against a fake `op` on PATH. The shim records
# every invocation to $OP_LOG and returns canned output, so we verify routing,
# document titles (full filename, no folder) and file placement without a real
# 1Password account. `jq` is the real one.

setup() {
    REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
    CLI="$REPO_ROOT/app-secrets.sh"

    WORKDIR="$(mktemp -d)"
    SHIMBIN="$WORKDIR/bin"
    mkdir -p "$SHIMBIN"
    OP_LOG="$WORKDIR/op.log"
    : > "$OP_LOG"

    cat > "$SHIMBIN/op" <<'SHIM'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$OP_LOG"

flag_val() {
    local want="$1"; shift
    local prev=""
    for a in "$@"; do
        [ "$prev" = "$want" ] && { printf '%s' "$a"; return 0; }
        prev="$a"
    done
}

if [ "$1" = whoami ]; then
    [ "${OP_FAKE_FAIL_WHOAMI:-}" = 1 ] && exit 1
    echo '{"user_uuid":"u1"}'
elif [ "$1" = vault ] && [ "$2" = list ]; then
    [ "${OP_FAKE_FAIL_VAULT_LIST:-}" = 1 ] && exit 1
    echo '[{"name":"v-staging"},{"name":"v-prod"}]'
elif [ "$1" = vault ] && [ "$2" = user ] && [ "$3" = list ]; then
    echo '[{"id":"user-1","permissions":["allow_viewing","allow_editing"]}]'
elif [ "$1" = user ] && [ "$2" = get ]; then
    echo '{"id":"user-1"}'
elif [ "$1" = item ] && [ "$2" = get ]; then
    exit 1   # item does not exist -> write should `document create`
elif [ "$1" = document ] && [ "$2" = get ]; then
    out=$(flag_val --out-file "$@")
    if [ -n "$out" ]; then
        mkdir -p "$(dirname "$out")"
        echo "secret-contents" > "$out"
    fi
fi
exit 0
SHIM
    chmod +x "$SHIMBIN/op"

    cat > "$WORKDIR/.secrets.config.json" <<'JSON'
{
  "vaults": [
    { "name": "staging", "vault": "v-staging",
      "files": ["Keys/Keys.staging.swift", "Config/Config.dev.json"] },
    { "name": "prod", "vault": "v-prod",
      "files": ["Keys/Keys.production.swift"] }
  ]
}
JSON

    export APP_SECRETS_SOURCES="$REPO_ROOT/sources"
    export OP_LOG
    export PATH="$SHIMBIN:$PATH"
    export TERM="${TERM:-xterm}"
    cd "$WORKDIR"
}

teardown() {
    cd /
    rm -rf "$WORKDIR"
}

@test "read fetches each file by full-filename title into its path" {
    run bash "$CLI" read
    [ "$status" -eq 0 ]

    [ -f "$WORKDIR/Keys/Keys.staging.swift" ]
    [ -f "$WORKDIR/Config/Config.dev.json" ]
    [ -f "$WORKDIR/Keys/Keys.production.swift" ]

    grep -q "document get Keys.staging.swift --vault v-staging --out-file Keys/Keys.staging.swift --force" "$OP_LOG"
    grep -q "document get Config.dev.json --vault v-staging --out-file Config/Config.dev.json --force" "$OP_LOG"
    grep -q "document get Keys.production.swift --vault v-prod --out-file Keys/Keys.production.swift --force" "$OP_LOG"
}

@test "read <label> restricts to that vault" {
    run bash "$CLI" read prod
    [ "$status" -eq 0 ]

    [ -f "$WORKDIR/Keys/Keys.production.swift" ]
    [ ! -f "$WORKDIR/Keys/Keys.staging.swift" ]
    ! grep -q "document get Keys.staging.swift" "$OP_LOG"
}

@test "write uploads existing files titled by filename (no folder)" {
    mkdir -p "$WORKDIR/Keys" "$WORKDIR/Config"
    echo v > "$WORKDIR/Keys/Keys.staging.swift"
    echo v > "$WORKDIR/Keys/Keys.production.swift"
    echo v > "$WORKDIR/Config/Config.dev.json"

    run bash "$CLI" write
    [ "$status" -eq 0 ]

    grep -q "document create Keys/Keys.staging.swift --title Keys.staging.swift --vault v-staging" "$OP_LOG"
    grep -q "document create Config/Config.dev.json --title Config.dev.json --vault v-staging" "$OP_LOG"
    grep -q "document create Keys/Keys.production.swift --title Keys.production.swift --vault v-prod" "$OP_LOG"
    ! grep -q -- "--title Keys/" "$OP_LOG"
}

@test "write <label> restricts to that vault" {
    mkdir -p "$WORKDIR/Keys"
    echo v > "$WORKDIR/Keys/Keys.staging.swift"
    echo v > "$WORKDIR/Keys/Keys.production.swift"

    run bash "$CLI" write staging
    [ "$status" -eq 0 ]

    grep -q "document create Keys/Keys.staging.swift --title Keys.staging.swift --vault v-staging" "$OP_LOG"
    ! grep -q "Keys.production.swift" "$OP_LOG"
}

@test "write errors when no configured files exist locally" {
    run bash "$CLI" write
    [ "$status" -ne 0 ]
    [[ "$output" == *"No local files to upload"* ]]
    ! grep -q "document create" "$OP_LOG"
}

@test "read establishes an op session before checking vault access" {
    run bash "$CLI" read
    [ "$status" -eq 0 ]
    [ "$(head -1 "$OP_LOG")" = "whoami" ]
}

@test "read proceeds when whoami fails but the app integration answers" {
    # `op whoami` only reports an existing session — with the desktop-app
    # integration it can fail while real commands (vault list) authorize fine.
    OP_FAKE_FAIL_WHOAMI=1 run bash "$CLI" read
    [ "$status" -eq 0 ]
    [ -f "$WORKDIR/Keys/Keys.staging.swift" ]
    [[ "$output" != *"not signed in"* ]]
}

@test "read fails fast with a sign-in hint when no op session is available" {
    OP_FAKE_FAIL_WHOAMI=1 OP_FAKE_FAIL_VAULT_LIST=1 run bash "$CLI" read
    [ "$status" -ne 0 ]
    [[ "$output" == *"not signed in to 1Password"* ]]
    ! grep -q "document get" "$OP_LOG"
    [[ "$output" != *"✗"* ]]
}

@test "write fails fast with a sign-in hint when no op session is available" {
    mkdir -p "$WORKDIR/Keys"
    echo v > "$WORKDIR/Keys/Keys.staging.swift"

    OP_FAKE_FAIL_WHOAMI=1 OP_FAKE_FAIL_VAULT_LIST=1 run bash "$CLI" write
    [ "$status" -ne 0 ]
    [[ "$output" == *"not signed in to 1Password"* ]]
    ! grep -q "document create" "$OP_LOG"
}
