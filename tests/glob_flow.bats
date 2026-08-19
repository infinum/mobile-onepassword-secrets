# tests/glob_flow.bats
# End-to-end flows for glob/folder patterns in 'files': write expands them
# against the local tree; read matches them against stored 'path' fields.

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
    refute grep -q "notes.txt" "$OP_LOG"

    grep -q "path\[text\]=Vault/sub/b.plist --vault v-staging" "$OP_LOG"
    grep -q "path\[text\]=Certs/my cert.pem --vault v-staging" "$OP_LOG"
}

@test "explicit entry overlapping a glob uploads once" {
    cat > .secrets.config.json <<'JSON'
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

@test "read downloads documents whose stored path matches a pattern" {
    seed_op_item v-staging Keys.staging.swift keys Keys/Keys.staging.swift > /dev/null
    ida=$(seed_op_item v-staging a.plist doc-a Vault/a.plist)
    idb=$(seed_op_item v-staging b.plist doc-b Vault/sub/b.plist)
    idother=$(seed_op_item v-staging x.plist doc-x Other/x.plist)
    idunstamped=$(seed_op_item v-staging c.plist doc-c)
    seed_op_item v-staging cert.pem doc-cert Certs/deep/cert.pem > /dev/null

    run bash "$CLI" read
    [ "$status" -eq 0 ]

    [ "$(cat Keys/Keys.staging.swift)" = "keys" ]
    [ "$(cat Vault/a.plist)" = "doc-a" ]
    [ "$(cat Vault/sub/b.plist)" = "doc-b" ]
    [ "$(cat Certs/deep/cert.pem)" = "doc-cert" ]
    [ ! -f Other/x.plist ]
    grep -q "document get $ida --vault v-staging --out-file Vault/a.plist --force" "$OP_LOG"
    grep -q "document get $idb --vault v-staging --out-file Vault/sub/b.plist --force" "$OP_LOG"
    refute grep -q "document get $idother" "$OP_LOG"
    refute grep -q "document get $idunstamped" "$OP_LOG"
}

@test "read refuses unsafe stored paths" {
    cat > .secrets.config.json <<'JSON'
{
  "vaults": [
    { "vault": "v-staging", "files": ["**"] }
  ]
}
JSON
    idevil=$(seed_op_item v-staging evil.txt evil ../evil.txt)
    idabs=$(seed_op_item v-staging abs.txt abs /etc/evil-abs.txt)
    iddash=$(seed_op_item v-staging dash.txt dash '-p/evil.txt')
    seed_op_item v-staging ok.txt ok Sub/ok.txt > /dev/null

    run bash "$CLI" read
    [ "$status" -ne 0 ]
    [[ "$output" == *"Refusing unsafe path"* ]]
    [ ! -f ../evil.txt ]
    [ ! -f /etc/evil-abs.txt ]
    [ ! -e ./-p ]
    [ "$(cat Sub/ok.txt)" = "ok" ]
    refute grep -q "document get $idevil" "$OP_LOG"
    refute grep -q "document get $idabs" "$OP_LOG"
    refute grep -q "document get $iddash" "$OP_LOG"
}

@test "read refuses stored paths that would hijack the next run" {
    cat > .secrets.config.json <<'JSON'
{
  "vaults": [
    { "vault": "v-staging", "files": ["**"] }
  ]
}
JSON
    mkdir -p .git/hooks
    echo '#!/bin/sh' > .git/hooks/post-checkout
    idhook=$(seed_op_item v-staging post-checkout 'pwned' .git/hooks/post-checkout)
    idconf=$(seed_op_item v-staging .secrets.config.json 'pwned' .secrets.config.json)
    idci=$(seed_op_item v-staging ci.yml 'pwned' .github/workflows/ci.yml)
    seed_op_item v-staging ok.txt ok Sub/ok.txt > /dev/null

    run bash "$CLI" read
    [ "$status" -ne 0 ]
    [[ "$output" == *"Refusing unsafe path"* ]]
    [ "$(cat .git/hooks/post-checkout)" = '#!/bin/sh' ]
    [ ! -f .github/workflows/ci.yml ]
    grep -q '"vaults"' .secrets.config.json
    [ "$(cat Sub/ok.txt)" = "ok" ]
    refute grep -q "document get $idhook" "$OP_LOG"
    refute grep -q "document get $idconf" "$OP_LOG"
    refute grep -q "document get $idci" "$OP_LOG"
}

@test "read fetches a document once when explicit and glob entries overlap" {
    cat > .secrets.config.json <<'JSON'
{
  "vaults": [
    { "vault": "v-staging", "files": ["Keys/Keys.staging.swift", "Keys/**"] }
  ]
}
JSON
    seed_op_item v-staging Keys.staging.swift keys Keys/Keys.staging.swift > /dev/null

    run bash "$CLI" read
    [ "$status" -eq 0 ]
    [ "$(grep -c "document get" "$OP_LOG")" -eq 1 ]
}

@test "read skips patterns for a vault it cannot list" {
    OP_FAKE_FAIL_ITEM_LIST=1 run bash "$CLI" read
    [ "$status" -ne 0 ]
    [[ "$output" == *"Could not list documents in 'v-staging'"* ]]
    [[ "$output" != *"Pattern matched no documents"* ]]
}

@test "read reports patterns matching no documents" {
    seed_op_item v-staging Keys.staging.swift keys Keys/Keys.staging.swift > /dev/null

    run bash "$CLI" read
    [ "$status" -eq 0 ]
    [[ "$output" == *"Pattern matched no documents in 'v-staging': Vault/**/*.plist"* ]]
    [[ "$output" == *"Pattern matched no documents in 'v-staging': Certs/"* ]]
}

@test "write points out the leftover item after a file moves" {
    cat > .secrets.config.json <<'JSON'
{
  "vaults": [
    { "vault": "v-staging", "files": ["Vault/**"] }
  ]
}
JSON
    mkdir -p Vault/Old
    echo k > Vault/Old/K.swift
    run bash "$CLI" write
    [ "$status" -eq 0 ]

    mkdir -p Vault/New
    mv Vault/Old/K.swift Vault/New/K.swift

    run bash "$CLI" write
    [ "$status" -eq 0 ]
    [[ "$output" == *"Vault/Old/K.swift"* ]]
    [[ "$output" == *"no local file"* ]]
    # The new location still uploads; this is a heads-up, not a blocker.
    grep -q "document create Vault/New/K.swift" "$OP_LOG"
}

@test "write says nothing about leftovers when files stay put" {
    mkdir -p Keys Vault Certs
    echo k > Keys/Keys.staging.swift
    echo a > Vault/a.plist
    echo c > Certs/c.pem

    run bash "$CLI" write
    [ "$status" -eq 0 ]

    run bash "$CLI" write
    [ "$status" -eq 0 ]
    [[ "$output" != *"no local file"* ]]
}

@test "read refuses to pick a winner between duplicate stamped paths" {
    cat > .secrets.config.json <<'JSON'
{
  "vaults": [
    { "vault": "v-staging", "files": ["Vault/**"] }
  ]
}
JSON
    seed_op_item v-staging a.plist first Vault/a.plist > /dev/null
    seed_op_item v-staging a.plist second Vault/a.plist > /dev/null
    seed_op_item v-staging b.plist fine Vault/b.plist > /dev/null

    run bash "$CLI" read
    [ "$status" -ne 0 ]
    [[ "$output" == *"more than one document in 'v-staging' is stamped 'Vault/a.plist'"* ]]
    [ ! -f Vault/a.plist ]
    [ "$(cat Vault/b.plist)" = "fine" ]
    refute grep -q -- "--out-file Vault/a.plist" "$OP_LOG"
}

@test "read lists a pattern-only vault once per run" {
    cat > .secrets.config.json <<'JSON'
{
  "vaults": [
    { "vault": "v-staging", "files": ["Vault/**", "Certs/", "Keys/"] }
  ]
}
JSON
    seed_op_item v-staging a.plist doc-a Vault/a.plist > /dev/null

    run bash "$CLI" read
    [ "$status" -eq 0 ]
    [ "$(grep -c "item list --vault v-staging" "$OP_LOG")" -eq 1 ]
}

@test "read <label> skips patterns for other vaults" {
    cat > .secrets.config.json <<'JSON'
{
  "vaults": [
    { "name": "staging", "vault": "v-staging", "files": ["Keys/Keys.staging.swift"] },
    { "name": "prod", "vault": "v-prod", "files": ["Prod/"] }
  ]
}
JSON
    seed_op_item v-staging Keys.staging.swift keys Keys/Keys.staging.swift > /dev/null
    idprod=$(seed_op_item v-prod p.pem prod Prod/p.pem)

    run bash "$CLI" read staging
    [ "$status" -eq 0 ]
    [ ! -f Prod/p.pem ]
    refute grep -q "document get $idprod" "$OP_LOG"
    refute grep -q "item list --vault v-prod" "$OP_LOG"
}

@test "write <label> skips patterns for other vaults" {
    cat > .secrets.config.json <<'JSON'
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
    refute grep -q "Prod/p.pem" "$OP_LOG"
}
