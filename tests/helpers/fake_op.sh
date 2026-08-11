#!/usr/bin/env bash
# tests/helpers/fake_op.sh — stateful fake `op` for the bats suite.
# Installed on PATH as `op` by setup_fake_op (tests/helpers/common.bash).
# Logs every invocation to $OP_LOG and keeps item state under $OP_STATE:
#   $OP_STATE/seq                  id counter
#   $OP_STATE/items/<id>/title     document title (one line)
#   $OP_STATE/items/<id>/vault     vault name
#   $OP_STATE/items/<id>/path      value of the custom 'path' field (optional)
#   $OP_STATE/items/<id>/content   document bytes
# Env toggles: OP_FAKE_BROKEN_CREATE=1 makes `document create --format json`
# print `{}` (no id) to exercise the caller's unparseable-id fallback;
# OP_FAKE_FAIL_ITEM_LIST=1 makes `item list` fail (transient op outage);
# OP_FAKE_FAIL_WHOAMI=1 makes `whoami` fail (no usable session);
# OP_FAKE_FAIL_DOC=<id> makes `document get/edit` fail for that one item;
# OP_FAKE_FAIL_DOC_ONCE=<id> fails only the first `document get/edit` for it,
# so a caller that reuses the id afterwards is caught.

printf '%s\n' "$*" >> "$OP_LOG"

STATE="${OP_STATE:?OP_STATE not set}"
mkdir -p "$STATE/items"

# Echoes the value following the given flag, or returns 1 if absent.
flag_val() {
    local want="$1"; shift
    local prev=""
    for a in "$@"; do
        [ "$prev" = "$want" ] && { printf '%s' "$a"; return 0; }
        prev="$a"
    done
    return 1
}

# Returns 0 (= this call should fail) when the id is the configured victim:
# always for OP_FAKE_FAIL_DOC, only on the first call for _ONCE.
should_fail_doc() {
    local id="$1"
    if [ -n "${OP_FAKE_FAIL_DOC:-}" ] && [ "$id" = "$OP_FAKE_FAIL_DOC" ]; then
        return 0
    fi
    if [ -n "${OP_FAKE_FAIL_DOC_ONCE:-}" ] && [ "$id" = "$OP_FAKE_FAIL_DOC_ONCE" ] \
       && [ ! -f "$STATE/failed-once-$id" ]; then
        : > "$STATE/failed-once-$id"
        return 0
    fi
    return 1
}

next_id() {
    local n=0
    [ -f "$STATE/seq" ] && n=$(cat "$STATE/seq")
    n=$((n + 1))
    printf '%s' "$n" > "$STATE/seq"
    printf 'item%04d' "$n"
}

# Echoes ids matching <arg> (an id, else a title), optionally scoped to <vault>.
resolve_ids() {
    local arg="$1" vault="$2" d id
    if [ -d "$STATE/items/$arg" ]; then
        echo "$arg"
        return 0
    fi
    for d in "$STATE/items"/*/; do
        [ -d "$d" ] || continue
        id=$(basename "$d")
        [ "$(cat "$d/title" 2>/dev/null)" = "$arg" ] || continue
        if [ -n "$vault" ] && [ "$(cat "$d/vault" 2>/dev/null)" != "$vault" ]; then
            continue
        fi
        echo "$id"
    done
}

# Echoes the full-item JSON (id, title, vault, fields) for an id.
item_json() {
    local d="$STATE/items/$1" fields="[]"
    if [ -f "$d/path" ]; then
        fields=$(jq -n --arg v "$(cat "$d/path")" \
            '[{"id":"f_path","type":"STRING","label":"path","value":$v}]')
    fi
    jq -n --arg id "$1" --arg t "$(cat "$d/title")" --arg vn "$(cat "$d/vault")" \
        --argjson f "$fields" \
        '{"id":$id,"title":$t,"vault":{"name":$vn},"fields":$f}'
}

cmd="${1:-}"
sub="${2:-}"

if [ "$cmd" = whoami ]; then
    echo '{"user_uuid":"u1"}'
    exit 0
fi

if [ "$cmd" = vault ] && [ "$sub" = list ]; then
    echo '[{"name":"v-staging"},{"name":"v-prod"}]'
    exit 0
fi

if [ "$cmd" = vault ] && [ "$sub" = user ] && [ "${3:-}" = list ]; then
    echo '[{"id":"user-1","permissions":["allow_viewing","allow_editing"]}]'
    exit 0
fi

if [ "$cmd" = user ] && [ "$sub" = get ]; then
    echo '{"id":"user-1"}'
    exit 0
fi

if [ "$cmd" = item ] && [ "$sub" = list ]; then
    [ "${OP_FAKE_FAIL_ITEM_LIST:-}" = 1 ] && exit 1
    vault=$(flag_val --vault "$@") || vault=""
    out="[]"
    for d in "$STATE/items"/*/; do
        [ -d "$d" ] || continue
        id=$(basename "$d")
        if [ -n "$vault" ] && [ "$(cat "$d/vault")" != "$vault" ]; then
            continue
        fi
        out=$(printf '%s' "$out" | jq --arg id "$id" --arg t "$(cat "$d/title")" \
            '. + [{"id":$id,"title":$t}]')
    done
    printf '%s\n' "$out"
    exit 0
fi

if [ "$cmd" = item ] && [ "$sub" = get ]; then
    arg="${3:-}"
    if [ "$arg" = "-" ]; then
        # Batch mode: a JSON array of {id,...} on stdin -> stream of full items.
        jq -r '.[].id' | while IFS= read -r id; do
            item_json "$id"
        done
        exit 0
    fi
    vault=$(flag_val --vault "$@") || vault=""
    ids=$(resolve_ids "$arg" "$vault")
    [ -z "$ids" ] && exit 1
    if [ "$(printf '%s\n' "$ids" | grep -c .)" -gt 1 ]; then
        echo "more than one item matches" >&2
        exit 1
    fi
    item_json "$ids"
    exit 0
fi

if [ "$cmd" = item ] && [ "$sub" = edit ]; then
    id="${3:-}"
    [ -d "$STATE/items/$id" ] || exit 1
    for a in "$@"; do
        case "$a" in
            "path[text]="*) printf '%s' "${a#path\[text\]=}" > "$STATE/items/$id/path" ;;
        esac
    done
    exit 0
fi

if [ "$cmd" = document ] && [ "$sub" = create ]; then
    file="${3:-}"
    title=$(flag_val --title "$@") || title=$(basename "$file")
    vault=$(flag_val --vault "$@") || vault=""
    id=$(next_id)
    mkdir -p "$STATE/items/$id"
    printf '%s' "$title" > "$STATE/items/$id/title"
    printf '%s' "$vault" > "$STATE/items/$id/vault"
    cp "$file" "$STATE/items/$id/content" 2>/dev/null || : > "$STATE/items/$id/content"
    if [ "${OP_FAKE_BROKEN_CREATE:-}" = 1 ]; then
        echo '{}'
    else
        # Deliberately the v1-style key: real `op document create` is a known
        # v1-holdout, and callers must parse `.id // .uuid`.
        printf '{"uuid":"%s","createdAt":"t","vaultUuid":"vv"}\n' "$id"
    fi
    exit 0
fi

if [ "$cmd" = document ] && [ "$sub" = edit ]; then
    arg="${3:-}"
    file="${4:-}"
    should_fail_doc "$arg" && exit 1
    vault=$(flag_val --vault "$@") || vault=""
    ids=$(resolve_ids "$arg" "$vault")
    [ -z "$ids" ] && exit 1
    if [ "$(printf '%s\n' "$ids" | grep -c .)" -gt 1 ]; then
        echo "more than one item matches" >&2
        exit 1
    fi
    cp "$file" "$STATE/items/$ids/content"
    exit 0
fi

if [ "$cmd" = document ] && [ "$sub" = get ]; then
    arg="${3:-}"
    should_fail_doc "$arg" && exit 1
    vault=$(flag_val --vault "$@") || vault=""
    out=$(flag_val --out-file "$@") || out=""
    ids=$(resolve_ids "$arg" "$vault")
    [ -z "$ids" ] && exit 1
    if [ "$(printf '%s\n' "$ids" | grep -c .)" -gt 1 ]; then
        echo "more than one item matches" >&2
        exit 1
    fi
    if [ -n "$out" ]; then
        mkdir -p "$(dirname "$out")"
        cp "$STATE/items/$ids/content" "$out"
    else
        cat "$STATE/items/$ids/content"
    fi
    exit 0
fi

# Unhandled subcommands succeed silently, like the old canned shim.
exit 0
