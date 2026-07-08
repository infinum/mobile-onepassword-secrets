# tests/op_flow.bats
# Exercises the read/write commands end-to-end against a fake `op` on PATH.
# The shim records every invocation to $OP_LOG and returns canned JSON, so we
# verify the mapping -> vault -> op-argument construction without a real
# 1Password account. `jq` is the real one.

setup() {
    REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
    CLI="$REPO_ROOT/infinum-secrets.sh"

    WORKDIR="$(mktemp -d)"
    SHIMBIN="$WORKDIR/bin"
    mkdir -p "$SHIMBIN"
    OP_LOG="$WORKDIR/op.log"
    : > "$OP_LOG"

    # Fake `op`: records args, returns canned output. bash 3.2 compatible.
    cat > "$SHIMBIN/op" <<'SHIM'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$OP_LOG"
if [ "$1" = vault ] && [ "$2" = list ]; then
    echo '[{"name":"v-prod"},{"name":"v-staging"}]'
elif [ "$1" = vault ] && [ "$2" = user ] && [ "$3" = list ]; then
    echo '[{"id":"user-1","permissions":["allow_viewing","allow_editing"]}]'
elif [ "$1" = user ] && [ "$2" = get ]; then
    echo '{"id":"user-1"}'
elif [ "$1" = item ] && [ "$2" = get ]; then
    # Pretend the item does not exist yet -> write should `document create`.
    exit 1
elif [ "$1" = document ] && [ "$2" = get ]; then
    prev=""; out=""
    for a in "$@"; do
        [ "$prev" = "--out-file" ] && out="$a"
        prev="$a"
    done
    if [ -n "$out" ]; then
        mkdir -p "$(dirname "$out")"
        echo "secret-contents" > "$out"
    fi
fi
exit 0
SHIM
    chmod +x "$SHIMBIN/op"

    # Config the commands will load from CWD.
    cat > "$WORKDIR/secrets.config.json" <<'JSON'
{
  "platform": "ios",
  "path": "vault",
  "environments": ["production", "staging"],
  "vaults": ["v-prod", "v-staging"],
  "files": [
    { "name": "Keys.swift", "environments": ["*"] }
  ],
  "fileVaults": [
    { "pattern": "*.staging.*", "vault": "v-staging" },
    { "pattern": "*.production.*", "vault": "v-prod" }
  ]
}
JSON

    export INFINUM_SECRETS_SOURCES="$REPO_ROOT/sources"
    export OP_LOG
    export PATH="$SHIMBIN:$PATH"
    export TERM="${TERM:-xterm}"   # deterministic tput/clear behavior under bats
    cd "$WORKDIR"
}

teardown() {
    cd /
    rm -rf "$WORKDIR"
}

@test "read downloads each env's doc from its mapped vault" {
    run bash "$CLI" read
    [ "$status" -eq 0 ]

    # Files landed in the configured path, split by basename.
    [ -f "$WORKDIR/vault/Keys/Keys.production.swift" ]
    [ -f "$WORKDIR/vault/Keys/Keys.staging.swift" ]

    # op was called with the right doc name + vault for each environment.
    grep -q "document get Keys.production --out-file .* --vault v-prod --force" "$OP_LOG"
    grep -q "document get Keys.staging --out-file .* --vault v-staging --force" "$OP_LOG"
}

@test "read <vault> only fetches from the requested vault" {
    run bash "$CLI" read v-staging
    [ "$status" -eq 0 ]

    grep -q "document get Keys.staging --out-file .* --vault v-staging --force" "$OP_LOG"
    ! grep -q "document get Keys.production" "$OP_LOG"
}

@test "write creates a new document in the mapped vault" {
    mkdir -p "$WORKDIR/vault/Upload"
    echo "value" > "$WORKDIR/vault/Upload/Keys.staging.swift"

    # Two interactive confirmations ("pulled?" and "upload these?") -> two blank lines.
    printf '\n\n' > "$WORKDIR/answers"
    run bash "$CLI" write Upload < "$WORKDIR/answers"
    [ "$status" -eq 0 ]

    # Item didn't exist (shim returns non-zero) -> create, titled by doc name, in v-staging.
    grep -q "document create .*/Keys.staging.swift --title Keys.staging --vault v-staging" "$OP_LOG"
}

@test "write skips files with no vault mapping and uploads nothing" {
    mkdir -p "$WORKDIR/vault/Unmapped"
    # Name matches neither fileVaults glob (no .staging./.production. segment).
    echo "value" > "$WORKDIR/vault/Unmapped/Keys.swift"

    printf '\n\n' > "$WORKDIR/answers"
    run bash "$CLI" write Unmapped < "$WORKDIR/answers"

    # No mappable files -> command bails out, nothing uploaded.
    [ "$status" -ne 0 ]
    [[ "$output" == *"No files with valid vault mappings"* ]]
    ! grep -q "document create" "$OP_LOG"
    ! grep -q "document edit" "$OP_LOG"
}
