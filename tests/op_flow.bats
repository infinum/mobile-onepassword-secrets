# tests/op_flow.bats
# Exercises read/write end-to-end against the stateful fake `op` on PATH
# (tests/helpers/fake_op.sh). The shim records every invocation to $OP_LOG and
# keeps item state under $OP_STATE, so we verify routing, document titles
# (full filename, no folder) and file placement without a real 1Password
# account. `jq` is the real one.

load helpers/common

setup() {
    REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
    CLI="$REPO_ROOT/app-secrets.sh"

    WORKDIR="$(mktemp -d)"
    setup_fake_op "$WORKDIR"

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
    export TERM="${TERM:-xterm}"
    cd "$WORKDIR"
}

teardown() {
    cd /
    rm -rf "$WORKDIR"
}

seed_configured_docs() {
    seed_op_item v-staging Keys.staging.swift secret-contents > /dev/null
    seed_op_item v-staging Config.dev.json secret-contents > /dev/null
    seed_op_item v-prod Keys.production.swift secret-contents > /dev/null
}

@test "read fetches each file by full-filename title into its path" {
    seed_configured_docs

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
    seed_configured_docs

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
