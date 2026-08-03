# tests/path_field.bats
# Unit tests for the path-field item resolution helpers (get_vault_items,
# resolve_item_for_path, stamp_item_path) against the stateful fake `op`.

load helpers/common

setup() {
    REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
    source "$REPO_ROOT/sources/__constants.sh"
    source "$REPO_ROOT/sources/helpers/__op_utils.sh"

    WORKDIR="$(mktemp -d)"
    setup_fake_op "$WORKDIR"
    cd "$WORKDIR"
}

teardown() {
    cd /
    rm -rf "$WORKDIR"
}

@test "get_vault_items returns full items with path fields" {
    seed_op_item v-staging GoogleService-Info.plist c1 Staging/GoogleService-Info.plist > /dev/null

    run get_vault_items v-staging
    [ "$status" -eq 0 ]
    echo "$output" | jq -e 'length == 1
        and .[0].title == "GoogleService-Info.plist"
        and (.[0].fields | any(.label == "path" and .value == "Staging/GoogleService-Info.plist"))'
}

@test "get_vault_items caches per vault (one op item list per vault)" {
    seed_op_item v-staging a.txt c1 a.txt > /dev/null

    get_vault_items v-staging > /dev/null
    get_vault_items v-staging > /dev/null
    [ "$(grep -c "item list --vault v-staging" "$OP_LOG")" -eq 1 ]

    get_vault_items v-prod > /dev/null
    [ "$(grep -c "item list --vault v-prod" "$OP_LOG")" -eq 1 ]
}

@test "get_vault_items returns [] for an empty vault without piping into item get" {
    run get_vault_items v-staging
    [ "$status" -eq 0 ]
    [ "$output" = "[]" ]
    ! grep -q "item get -" "$OP_LOG"
}

@test "resolve reports none in an empty vault" {
    run resolve_item_for_path v-staging Keys/Keys.swift
    [ "$status" -eq 0 ]
    [ "$output" = "none" ]
}

@test "resolve finds the exact path match among same-title items" {
    id1=$(seed_op_item v-staging GoogleService-Info.plist c1 Staging/GoogleService-Info.plist)
    id2=$(seed_op_item v-staging GoogleService-Info.plist c2 Production/GoogleService-Info.plist)

    run resolve_item_for_path v-staging Production/GoogleService-Info.plist
    [ "$output" = "found $id2" ]

    run resolve_item_for_path v-staging Staging/GoogleService-Info.plist
    [ "$output" = "found $id1" ]
}

@test "resolve reports ambiguous when two items carry the same path stamp" {
    seed_op_item v-staging K.swift c1 Keys/K.swift > /dev/null
    seed_op_item v-staging K.swift c2 Keys/K.swift > /dev/null

    run resolve_item_for_path v-staging Keys/K.swift
    [ "$output" = "ambiguous" ]
}

@test "resolve reports none when all title-mates are stamped with other paths" {
    seed_op_item v-staging GoogleService-Info.plist c1 Staging/GoogleService-Info.plist > /dev/null

    run resolve_item_for_path v-staging Production/GoogleService-Info.plist
    [ "$output" = "none" ]
}

@test "resolve adopts a single unstamped title match" {
    id=$(seed_op_item v-staging Keys.swift c1)

    run resolve_item_for_path v-staging Keys/Keys.swift
    [ "$output" = "adopt $id" ]
}

@test "resolve reports ambiguous for multiple candidates with an unstamped one" {
    seed_op_item v-staging K.swift c1 > /dev/null
    seed_op_item v-staging K.swift c2 Other/K.swift > /dev/null

    run resolve_item_for_path v-staging Keys/K.swift
    [ "$output" = "ambiguous" ]
}

@test "resolve excludes claimed ids" {
    id=$(seed_op_item v-staging K.swift c1)

    run resolve_item_for_path v-staging Keys/K.swift "$id"
    [ "$output" = "none" ]
}

@test "resolve does not match items from other vaults" {
    seed_op_item v-prod Keys.swift c1 Keys/Keys.swift > /dev/null

    run resolve_item_for_path v-staging Keys/Keys.swift
    [ "$output" = "none" ]
}

@test "stamp_item_path sets the path field on the item" {
    id=$(seed_op_item v-staging Keys.swift c1)

    run stamp_item_path "$id" Keys/Keys.swift v-staging
    [ "$status" -eq 0 ]
    [ "$(cat "$OP_STATE/items/$id/path")" = "Keys/Keys.swift" ]
    grep -q "item edit $id path\[text\]=Keys/Keys.swift --vault v-staging" "$OP_LOG"
}
