# tests/helpers/common.bash — shared setup for suites exercising the fake op.

# Installs the stateful fake `op` shim on PATH and initializes its state/log.
# Usage (from setup()): setup_fake_op "$WORKDIR"
# Exports: OP_LOG, OP_STATE; prepends the shim dir to PATH.
setup_fake_op() {
    local workdir="$1"
    SHIMBIN="$workdir/bin"
    mkdir -p "$SHIMBIN"
    OP_LOG="$workdir/op.log"
    : > "$OP_LOG"
    OP_STATE="$workdir/op-state"
    mkdir -p "$OP_STATE/items"
    cp "$(dirname "$BATS_TEST_FILENAME")/helpers/fake_op.sh" "$SHIMBIN/op"
    chmod +x "$SHIMBIN/op"
    export OP_LOG OP_STATE
    export PATH="$SHIMBIN:$PATH"
    return 0
}

# Seeds an item into the fake op state; echoes its id.
# Usage: seed_op_item <vault> <title> <content> [path]
seed_op_item() {
    local vault="$1" title="$2" content="$3" path="${4:-}"
    local n id
    n=$(cat "$OP_STATE/seq" 2>/dev/null || echo 0)
    n=$((n + 1))
    printf '%s' "$n" > "$OP_STATE/seq"
    id=$(printf 'item%04d' "$n")
    mkdir -p "$OP_STATE/items/$id"
    printf '%s' "$title" > "$OP_STATE/items/$id/title"
    printf '%s' "$vault" > "$OP_STATE/items/$id/vault"
    printf '%s' "$content" > "$OP_STATE/items/$id/content"
    if [ -n "$path" ]; then
        printf '%s' "$path" > "$OP_STATE/items/$id/path"
    fi
    echo "$id"
    return 0
}
