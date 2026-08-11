# tests/exit_codes.bats
# The exit-code contract. CI runs `read` to get its secrets and `write` to
# publish them, so anything that leaves a configured file out of sync must be
# visible in $?. Patterns are the exception: they describe "whatever is there",
# and matching nothing is a legitimate state, not a failure.

load helpers/common

setup() {
    REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
    CLI="$REPO_ROOT/infinum-secrets.sh"

    WORKDIR="$(mktemp -d)"
    setup_fake_op "$WORKDIR"

    cat > "$WORKDIR/.secrets.config.json" <<'JSON'
{
  "vaults": [
    { "name": "staging", "vault": "v-staging",
      "files": ["Keys/Keys.staging.swift"] }
  ]
}
JSON

    export INFINUM_SECRETS_SOURCES="$REPO_ROOT/sources"
    export TERM="${TERM:-xterm}"
    cd "$WORKDIR"
}

teardown() {
    cd /
    rm -rf "$WORKDIR"
}

# --- read --------------------------------------------------------------------

@test "read exits zero when every configured file arrives" {
    seed_op_item v-staging Keys.staging.swift keys Keys/Keys.staging.swift > /dev/null

    run bash "$CLI" read
    [ "$status" -eq 0 ]
    [[ "$output" == *"Done!"* ]]
}

@test "read exits non-zero when a configured document is missing" {
    run bash "$CLI" read
    [ "$status" -ne 0 ]
    [[ "$output" == *"No document in 'v-staging'"* ]]
}

@test "read exits non-zero when a fetch fails" {
    id=$(seed_op_item v-staging Keys.staging.swift keys Keys/Keys.staging.swift)

    OP_FAKE_FAIL_DOC=$id run bash "$CLI" read
    [ "$status" -ne 0 ]
    [[ "$output" == *"Could not fetch document"* ]]
}

@test "read exits non-zero when a vault cannot be listed" {
    OP_FAKE_FAIL_ITEM_LIST=1 run bash "$CLI" read
    [ "$status" -ne 0 ]
    [[ "$output" == *"Could not list documents"* ]]
}

@test "read exits non-zero when a configured vault is inaccessible" {
    cat > .secrets.config.json <<'JSON'
{
  "vaults": [
    { "vault": "v-staging", "files": ["Keys/Keys.staging.swift"] },
    { "vault": "v-missing", "files": ["Keys/Keys.other.swift"] }
  ]
}
JSON
    seed_op_item v-staging Keys.staging.swift keys Keys/Keys.staging.swift > /dev/null

    run bash "$CLI" read
    [ "$status" -ne 0 ]
    [[ "$output" == *"No access to 'v-missing'"* ]]
    [ "$(cat Keys/Keys.staging.swift)" = "keys" ]
}

@test "read exits non-zero when it refuses an unsafe stored path" {
    cat > .secrets.config.json <<'JSON'
{
  "vaults": [
    { "vault": "v-staging", "files": ["**"] }
  ]
}
JSON
    seed_op_item v-staging evil.txt evil ../evil.txt > /dev/null

    run bash "$CLI" read
    [ "$status" -ne 0 ]
    [[ "$output" == *"Refusing unsafe path"* ]]
}

@test "read exits non-zero when a document cannot be resolved" {
    seed_op_item v-staging Keys.staging.swift c1 > /dev/null
    seed_op_item v-staging Keys.staging.swift c2 > /dev/null

    run bash "$CLI" read
    [ "$status" -ne 0 ]
    [[ "$output" == *"Cannot uniquely resolve"* ]]
}

@test "read exits zero when a pattern matches no documents" {
    cat > .secrets.config.json <<'JSON'
{
  "vaults": [
    { "vault": "v-staging", "files": ["Certs/"] }
  ]
}
JSON

    run bash "$CLI" read
    [ "$status" -eq 0 ]
    [[ "$output" == *"Pattern matched no documents"* ]]
}

# --- write -------------------------------------------------------------------

@test "write exits zero when every file uploads" {
    mkdir -p Keys
    echo k > Keys/Keys.staging.swift

    run bash "$CLI" write
    [ "$status" -eq 0 ]
    [[ "$output" == *"Done!"* ]]
}

@test "write exits non-zero when an upload fails" {
    id=$(seed_op_item v-staging Keys.staging.swift old Keys/Keys.staging.swift)
    mkdir -p Keys
    echo k > Keys/Keys.staging.swift

    OP_FAKE_FAIL_DOC=$id run bash "$CLI" write
    [ "$status" -ne 0 ]
    [[ "$output" == *"Could not upload"* ]]
}

@test "write exits non-zero when a document cannot be resolved" {
    seed_op_item v-staging Keys.staging.swift c1 > /dev/null
    seed_op_item v-staging Keys.staging.swift c2 > /dev/null
    mkdir -p Keys
    echo k > Keys/Keys.staging.swift

    run bash "$CLI" write
    [ "$status" -ne 0 ]
    [[ "$output" == *"Cannot uniquely resolve"* ]]
}

@test "write exits non-zero when a vault cannot be listed" {
    mkdir -p Keys
    echo k > Keys/Keys.staging.swift

    OP_FAKE_FAIL_ITEM_LIST=1 run bash "$CLI" write
    [ "$status" -ne 0 ]
    [[ "$output" == *"Could not list documents"* ]]
}

@test "write exits non-zero when the new item id cannot be read" {
    mkdir -p Keys
    echo k > Keys/Keys.staging.swift

    OP_FAKE_BROKEN_CREATE=1 run bash "$CLI" write
    [ "$status" -ne 0 ]
    [[ "$output" == *"could not read the new item id"* ]]
}

@test "write exits zero when a pattern matches no local files" {
    cat > .secrets.config.json <<'JSON'
{
  "vaults": [
    { "vault": "v-staging", "files": ["Keys/Keys.staging.swift", "Certs/"] }
  ]
}
JSON
    mkdir -p Keys
    echo k > Keys/Keys.staging.swift

    run bash "$CLI" write
    [ "$status" -eq 0 ]
    [[ "$output" == *"Pattern matched no local files"* ]]
}

@test "write exits zero when a configured file is missing locally" {
    cat > .secrets.config.json <<'JSON'
{
  "vaults": [
    { "vault": "v-staging",
      "files": ["Keys/Keys.staging.swift", "Keys/Keys.absent.swift"] }
  ]
}
JSON
    mkdir -p Keys
    echo k > Keys/Keys.staging.swift

    run bash "$CLI" write
    [ "$status" -eq 0 ]
    [[ "$output" == *"Local file missing, skipping"* ]]
}
