# tests/glob_flow.bats
# End-to-end flows for glob/folder patterns in 'files': write expands them
# against the local tree; read matches them against stored 'path' fields.

load helpers/common

setup() {
    REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
    CLI="$REPO_ROOT/infinum-secrets.sh"

    WORKDIR="$(mktemp -d)"
    setup_fake_op "$WORKDIR"

    cat > "$WORKDIR/secrets.config.json" <<'JSON'
{
  "vaults": [
    { "name": "staging", "vault": "v-staging",
      "files": [
        "Keys/Keys.staging.swift",
        "Vault/**/*.plist",
        "Certs/"
      ] }
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

@test "write expands glob and folder patterns and stamps each match" {
    mkdir -p Keys Vault/sub Certs/deep
    echo k > Keys/Keys.staging.swift
    echo a > Vault/a.plist
    echo b > Vault/sub/b.plist
    echo n > Vault/notes.txt
    echo c > "Certs/my cert.pem"
    echo d > Certs/deep/d.pem

    run bash "$CLI" write
    [ "$status" -eq 0 ]

    [ "$(grep -c "document create" "$OP_LOG")" -eq 5 ]
    grep -q "document create Vault/a.plist --title a.plist --vault v-staging" "$OP_LOG"
    grep -q "document create Vault/sub/b.plist --title b.plist --vault v-staging" "$OP_LOG"
    grep -q "document create Certs/my cert.pem --title my cert.pem --vault v-staging" "$OP_LOG"
    grep -q "document create Certs/deep/d.pem --title d.pem --vault v-staging" "$OP_LOG"
    ! grep -q "notes.txt" "$OP_LOG"

    grep -q "path\[text\]=Vault/sub/b.plist --vault v-staging" "$OP_LOG"
    grep -q "path\[text\]=Certs/my cert.pem --vault v-staging" "$OP_LOG"
}

@test "explicit entry overlapping a glob uploads once" {
    cat > secrets.config.json <<'JSON'
{
  "vaults": [
    { "vault": "v-staging",
      "files": ["Vault/Keys/K.swift", "Vault/**"] }
  ]
}
JSON
    mkdir -p Vault/Keys
    echo k > Vault/Keys/K.swift

    run bash "$CLI" write
    [ "$status" -eq 0 ]
    [ "$(grep -c "document create" "$OP_LOG")" -eq 1 ]
    [ "$(grep -c "document create Vault/Keys/K.swift" "$OP_LOG")" -eq 1 ]
}

@test "write warns when a pattern matches nothing locally and continues" {
    mkdir -p Keys
    echo k > Keys/Keys.staging.swift

    run bash "$CLI" write
    [ "$status" -eq 0 ]
    [[ "$output" == *"Pattern matched no local files: Vault/**/*.plist"* ]]
    [[ "$output" == *"Pattern matched no local files: Certs/"* ]]
    grep -q "document create Keys/Keys.staging.swift" "$OP_LOG"
}

@test "write <label> skips patterns for other vaults" {
    cat > secrets.config.json <<'JSON'
{
  "vaults": [
    { "name": "staging", "vault": "v-staging", "files": ["Keys/Keys.staging.swift"] },
    { "name": "prod", "vault": "v-prod", "files": ["Prod/"] }
  ]
}
JSON
    mkdir -p Keys Prod
    echo k > Keys/Keys.staging.swift
    echo p > Prod/p.pem

    run bash "$CLI" write staging
    [ "$status" -eq 0 ]
    ! grep -q "Prod/p.pem" "$OP_LOG"
}
