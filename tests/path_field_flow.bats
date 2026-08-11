# tests/path_field_flow.bats
# End-to-end write/read flows for path-field disambiguation: same-named files
# in one vault resolve to distinct items via the 'path' custom field, and all
# op document operations go through item ids after resolution.

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
        "Staging/GoogleService-Info.plist",
        "Production/GoogleService-Info.plist",
        "Keys/Keys.staging.swift"
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

seed_local_duplicates() {
    mkdir -p Staging Production
    echo staging-plist > Staging/GoogleService-Info.plist
    echo production-plist > Production/GoogleService-Info.plist
}

@test "write creates distinct items for same-named files and stamps each path" {
    seed_local_duplicates

    run bash "$CLI" write
    [ "$status" -eq 0 ]

    [ "$(grep -c "document create" "$OP_LOG")" -eq 2 ]
    grep -q "document create Staging/GoogleService-Info.plist --title GoogleService-Info.plist --vault v-staging --format json" "$OP_LOG"
    grep -q "document create Production/GoogleService-Info.plist --title GoogleService-Info.plist --vault v-staging --format json" "$OP_LOG"
    grep -q "item edit item0001 path\[text\]=Staging/GoogleService-Info.plist --vault v-staging" "$OP_LOG"
    grep -q "item edit item0002 path\[text\]=Production/GoogleService-Info.plist --vault v-staging" "$OP_LOG"

    [ "$(cat "$OP_STATE/items/item0001/path")" = "Staging/GoogleService-Info.plist" ]
    [ "$(cat "$OP_STATE/items/item0002/path")" = "Production/GoogleService-Info.plist" ]
    [ "$(cat "$OP_STATE/items/item0001/content")" = "staging-plist" ]
    [ "$(cat "$OP_STATE/items/item0002/content")" = "production-plist" ]
}

@test "second write edits each item by id without creating new ones" {
    seed_local_duplicates
    run bash "$CLI" write
    [ "$status" -eq 0 ]

    echo staging-v2 > Staging/GoogleService-Info.plist
    run bash "$CLI" write
    [ "$status" -eq 0 ]

    [ "$(grep -c "document create" "$OP_LOG")" -eq 2 ]
    grep -q "document edit item0001 Staging/GoogleService-Info.plist --vault v-staging" "$OP_LOG"
    grep -q "document edit item0002 Production/GoogleService-Info.plist --vault v-staging" "$OP_LOG"
    [ "$(cat "$OP_STATE/items/item0001/content")" = "staging-v2" ]
}

@test "write adopts a single unstamped title match and stamps it" {
    id=$(seed_op_item v-staging Keys.staging.swift old-content)
    mkdir -p Keys
    echo new-content > Keys/Keys.staging.swift

    run bash "$CLI" write
    [ "$status" -eq 0 ]

    grep -q "document edit $id Keys/Keys.staging.swift --vault v-staging" "$OP_LOG"
    grep -q "item edit $id path\[text\]=Keys/Keys.staging.swift --vault v-staging" "$OP_LOG"
    refute grep -q "document create" "$OP_LOG"
    [ "$(cat "$OP_STATE/items/$id/content")" = "new-content" ]
}

@test "write skips when several unstamped items share the title" {
    seed_op_item v-staging GoogleService-Info.plist c1 > /dev/null
    seed_op_item v-staging GoogleService-Info.plist c2 > /dev/null
    mkdir -p Staging
    echo local > Staging/GoogleService-Info.plist

    run bash "$CLI" write
    [ "$status" -eq 0 ]
    [[ "$output" == *"Cannot uniquely resolve document 'GoogleService-Info.plist'"* ]]
    refute grep -q "document create" "$OP_LOG"
    refute grep -q "document edit" "$OP_LOG"
}

@test "write warns when the new item id is unparseable, then the next write adopts" {
    mkdir -p Staging
    echo local > Staging/GoogleService-Info.plist

    OP_FAKE_BROKEN_CREATE=1 run bash "$CLI" write
    [ "$status" -eq 0 ]
    [[ "$output" == *"could not read the new item id"* ]]
    refute grep -q "item edit" "$OP_LOG"

    run bash "$CLI" write
    [ "$status" -eq 0 ]
    [ "$(grep -c "document create" "$OP_LOG")" -eq 1 ]
    grep -q "document edit item0001 Staging/GoogleService-Info.plist --vault v-staging" "$OP_LOG"
    grep -q "item edit item0001 path\[text\]=Staging/GoogleService-Info.plist --vault v-staging" "$OP_LOG"
}

@test "write lists each vault's items once per run" {
    seed_local_duplicates

    run bash "$CLI" write
    [ "$status" -eq 0 ]
    [ "$(grep -c "item list --vault v-staging" "$OP_LOG")" -eq 1 ]
}

@test "read fetches same-titled items to their own paths by id" {
    id1=$(seed_op_item v-staging GoogleService-Info.plist staging-doc Staging/GoogleService-Info.plist)
    id2=$(seed_op_item v-staging GoogleService-Info.plist production-doc Production/GoogleService-Info.plist)
    seed_op_item v-staging Keys.staging.swift keys-doc Keys/Keys.staging.swift > /dev/null

    run bash "$CLI" read
    [ "$status" -eq 0 ]

    [ "$(cat Staging/GoogleService-Info.plist)" = "staging-doc" ]
    [ "$(cat Production/GoogleService-Info.plist)" = "production-doc" ]
    [ "$(cat Keys/Keys.staging.swift)" = "keys-doc" ]
    grep -q "document get $id1 --vault v-staging --out-file Staging/GoogleService-Info.plist --force" "$OP_LOG"
    grep -q "document get $id2 --vault v-staging --out-file Production/GoogleService-Info.plist --force" "$OP_LOG"
}

@test "read adopts a single unstamped title match without stamping" {
    seed_op_item v-staging Keys.staging.swift keys-doc > /dev/null

    run bash "$CLI" read
    [ "$status" -eq 0 ]
    [ "$(cat Keys/Keys.staging.swift)" = "keys-doc" ]
    refute grep -q "item edit" "$OP_LOG"
}

@test "read reports missing documents and continues" {
    run bash "$CLI" read
    [ "$status" -eq 0 ]
    [[ "$output" == *"No document in 'v-staging' for Staging/GoogleService-Info.plist"* ]]
    [[ "$output" == *"Done!"* ]]
}

@test "read skips ambiguous title matches and continues" {
    seed_op_item v-staging GoogleService-Info.plist c1 > /dev/null
    seed_op_item v-staging GoogleService-Info.plist c2 > /dev/null

    run bash "$CLI" read
    [ "$status" -eq 0 ]
    [[ "$output" == *"Cannot uniquely resolve document 'GoogleService-Info.plist'"* ]]
    [ ! -f Staging/GoogleService-Info.plist ]
    [ ! -f Production/GoogleService-Info.plist ]
}

@test "read does not adopt the same item for two entries" {
    seed_op_item v-staging GoogleService-Info.plist only-one > /dev/null

    run bash "$CLI" read
    [ "$status" -eq 0 ]
    [ "$(cat Staging/GoogleService-Info.plist)" = "only-one" ]
    [ ! -f Production/GoogleService-Info.plist ]
    [ "$(grep -c "document get" "$OP_LOG")" -eq 1 ]
}

@test "read does not reuse an item whose download failed" {
    id=$(seed_op_item v-staging GoogleService-Info.plist staging-doc)

    OP_FAKE_FAIL_DOC_ONCE=$id run bash "$CLI" read
    [[ "$output" == *"Could not fetch document"* ]]

    # The id was spent on the first entry; reusing it would drop the staging
    # document into the production path.
    [ ! -f Production/GoogleService-Info.plist ]
    [ "$(grep -c "document get" "$OP_LOG")" -eq 1 ]
}

@test "write does not reuse an item whose upload failed" {
    seed_local_duplicates
    id=$(seed_op_item v-staging GoogleService-Info.plist old-content)

    OP_FAKE_FAIL_DOC_ONCE=$id run bash "$CLI" write
    [[ "$output" == *"Could not upload"* ]]

    # Reusing the id would overwrite the item with the production file and
    # stamp it with the production path.
    [ "$(cat "$OP_STATE/items/$id/content")" = "old-content" ]
    refute test -f "$OP_STATE/items/$id/path"
    refute grep -q "document edit $id Production/GoogleService-Info.plist" "$OP_LOG"
}

@test "write uploads a duplicated literal entry only once" {
    cat > secrets.config.json <<'JSON'
{
  "vaults": [
    { "vault": "v-staging",
      "files": ["Keys/Keys.staging.swift", "Keys/Keys.staging.swift"] }
  ]
}
JSON
    mkdir -p Keys
    echo k > Keys/Keys.staging.swift

    run bash "$CLI" write
    [ "$status" -eq 0 ]
    [ "$(grep -c "document create" "$OP_LOG")" -eq 1 ]

    run bash "$CLI" write
    [ "$status" -eq 0 ]
    [ "$(grep -c "document create" "$OP_LOG")" -eq 1 ]
    [[ "$output" != *"Cannot uniquely resolve"* ]]
}

@test "write skips a vault it cannot list instead of creating duplicates" {
    seed_local_duplicates

    OP_FAKE_FAIL_ITEM_LIST=1 run bash "$CLI" write
    [ "$status" -eq 0 ]
    [[ "$output" == *"Could not list documents in 'v-staging'"* ]]
    refute grep -q "document create" "$OP_LOG"
}

@test "read skips a vault it cannot list instead of reporting missing" {
    seed_op_item v-staging Keys.staging.swift keys Keys/Keys.staging.swift > /dev/null

    OP_FAKE_FAIL_ITEM_LIST=1 run bash "$CLI" read
    [ "$status" -eq 0 ]
    [[ "$output" == *"Could not list documents in 'v-staging'"* ]]
    [[ "$output" != *"No document in"* ]]
    refute grep -q "document get" "$OP_LOG"
}

@test "write scopes item listing to document items" {
    seed_local_duplicates

    run bash "$CLI" write
    [ "$status" -eq 0 ]
    grep -q "item list --vault v-staging --categories Document --format json" "$OP_LOG"
}

@test "read lists each vault's items once per run" {
    seed_op_item v-staging Keys.staging.swift k Keys/Keys.staging.swift > /dev/null

    run bash "$CLI" read
    [ "$status" -eq 0 ]
    [ "$(grep -c "item list --vault v-staging" "$OP_LOG")" -eq 1 ]
}
