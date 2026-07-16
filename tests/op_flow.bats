# tests/op_flow.bats
# Exercises read/write end-to-end against a fake `op` on PATH. The shim records
# every invocation to $OP_LOG and returns canned JSON, so we verify the
# pattern -> vault routing and op-argument construction without a real
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

# extract the value following a flag, e.g. flag_val --vault  -> vault name
flag_val() {
    local want="$1"; shift
    local prev=""
    for a in "$@"; do
        [ "$prev" = "$want" ] && { printf '%s' "$a"; return 0; }
        prev="$a"
    done
    return 0
}

if [ "$1" = vault ] && [ "$2" = list ]; then
    echo '[{"name":"v-staging"},{"name":"v-prod"}]'
elif [ "$1" = vault ] && [ "$2" = user ] && [ "$3" = list ]; then
    echo '[{"id":"user-1","permissions":["allow_viewing","allow_editing"]}]'
elif [ "$1" = user ] && [ "$2" = get ]; then
    echo '{"id":"user-1"}'
elif [ "$1" = document ] && [ "$2" = list ]; then
    v=$(flag_val --vault "$@")
    if [ "$v" = v-staging ]; then
        echo '[{"title":"Keys.staging.swift"},{"title":"Notes.dev.swift"},{"title":"random.txt"}]'
    elif [ "$v" = v-prod ]; then
        echo '[{"title":"Keys.production.swift"}]'
    else
        echo '[]'
    fi
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

    cat > "$WORKDIR/secrets.config.json" <<'JSON'
{
  "platform": "ios",
  "path": "vault",
  "vaults": [
    { "name": "v-staging", "patterns": ["*.staging.*", "*.dev.*"] },
    { "name": "v-prod",    "patterns": ["*.production.*"] }
  ]
}
JSON

    export INFINUM_SECRETS_SOURCES="$REPO_ROOT/sources"
    export OP_LOG
    export PATH="$SHIMBIN:$PATH"
    export TERM="${TERM:-xterm}"
    cd "$WORKDIR"
}

teardown() {
    cd /
    rm -rf "$WORKDIR"
}

@test "read downloads only pattern-matching docs, preserving names" {
    run bash "$CLI" read
    [ "$status" -eq 0 ]

    # Matched by *.staging.* / *.dev.* / *.production.*
    [ -f "$WORKDIR/vault/Keys.staging.swift" ]
    [ -f "$WORKDIR/vault/Notes.dev.swift" ]
    [ -f "$WORKDIR/vault/Keys.production.swift" ]

    # random.txt matches no vault pattern -> not downloaded.
    [ ! -f "$WORKDIR/vault/random.txt" ]

    grep -q "document get Keys.staging.swift --vault v-staging --out-file .* --force" "$OP_LOG"
    grep -q "document get Keys.production.swift --vault v-prod --out-file .* --force" "$OP_LOG"
    ! grep -q "document get random.txt" "$OP_LOG"
}

@test "read <vault> restricts to the requested vault" {
    run bash "$CLI" read v-prod
    [ "$status" -eq 0 ]

    [ -f "$WORKDIR/vault/Keys.production.swift" ]
    [ ! -f "$WORKDIR/vault/Keys.staging.swift" ]
    ! grep -q "document list --vault v-staging" "$OP_LOG"
}

@test "write routes files to vaults by relative path and titles them by relpath" {
    mkdir -p "$WORKDIR/vault/nested"
    echo v > "$WORKDIR/vault/Keys.staging.swift"
    echo v > "$WORKDIR/vault/nested/App.production.swift"

    printf '\n\n' > "$WORKDIR/answers"
    run bash "$CLI" write < "$WORKDIR/answers"
    [ "$status" -eq 0 ]

    grep -q "document create vault/Keys.staging.swift --title Keys.staging.swift --vault v-staging" "$OP_LOG"
    grep -q "document create vault/nested/App.production.swift --title nested/App.production.swift --vault v-prod" "$OP_LOG"
}

@test "write skips unmapped files and uploads nothing when none match" {
    mkdir -p "$WORKDIR/vault/Unmapped"
    echo v > "$WORKDIR/vault/Unmapped/Keys.swift"   # no .staging./.dev./.production.

    printf '\n\n' > "$WORKDIR/answers"
    run bash "$CLI" write < "$WORKDIR/answers"

    [ "$status" -ne 0 ]
    [[ "$output" == *"No files matched any vault pattern"* ]]
    ! grep -q "document create" "$OP_LOG"
    ! grep -q "document edit" "$OP_LOG"
}
