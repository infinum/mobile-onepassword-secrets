#!/usr/bin/env bash
# sources/helpers/__path_utils.sh
# Glob/folder pattern helpers for 'files' config entries. Sourcing is
# side-effect-free. Pattern dialect (documented in the README):
#   *   matches within one path component (never crosses /)
#   ?   matches one character within a component
#   **  crosses directories; '**/' matches zero or more whole directories
#   dir/ (trailing slash) is shorthand for dir/**
# One translator serves both sides of a sync: write matches local files,
# read matches the 'path' fields stored on 1Password items.

# True if a config entry is a pattern rather than a literal file path.
is_glob_entry() {
    case "$1" in
        *'*'*|*'?'*|*/) return 0 ;;
    esac
    return 1
}

# Expands the trailing-slash folder shorthand: 'Vault/Keys/' -> 'Vault/Keys/**'.
normalize_pattern() {
    local p="$1"
    if [[ "$p" == */ ]]; then
        p="${p}**"
    fi
    printf '%s\n' "$p"
}

# Translates a glob pattern to an anchored ERE (bash 3.2: no globstar, so the
# scanner hand-rolls '**'). Regex metacharacters in the pattern stay literal.
glob_to_regex() {
    local pat="$1" out="" i=0 c
    while [[ "$i" -lt "${#pat}" ]]; do
        c="${pat:$i:1}"
        if [[ "$c" == '*' ]]; then
            if [[ "${pat:$i:2}" == '**' ]]; then
                if [[ "${pat:$((i + 2)):1}" == '/' ]]; then
                    out="${out}([^/]+/)*"   # '**/': zero or more whole dirs
                    i=$((i + 3))
                    continue
                fi
                out="${out}.*"              # trailing or bare '**'
                i=$((i + 2))
                continue
            fi
            out="${out}[^/]*"
        elif [[ "$c" == '?' ]]; then
            out="${out}[^/]"
        else
            # SC1003: the last arm is a literal backslash, not a quote escape.
            # shellcheck disable=SC1003
            case "$c" in
                '.'|'+'|'('|')'|'^'|'$'|'|'|'{'|'}'|'['|']'|'\') out="${out}\\${c}" ;;
                *) out="${out}${c}" ;;
            esac
        fi
        i=$((i + 1))
    done
    printf '^%s$\n' "$out"
}

# Returns 0 if the path matches the (un-normalized) pattern.
path_matches_pattern() {
    local regex
    regex=$(glob_to_regex "$(normalize_pattern "$2")")
    printf '%s\n' "$1" | grep -Eq "$regex"
}

# Echoes repo-relative local files matching the pattern, sorted, one per line.
# Always returns 0; no matches means no output.
expand_glob_local() {
    local regex
    regex=$(glob_to_regex "$(normalize_pattern "$1")")
    find . -name .git -prune -o -type f -print 2>/dev/null \
        | sed 's|^\./||' | grep -E "$regex" | sort || true
    return 0
}

# Safety gate for paths that arrive from a remote 'path' field: they become
# filesystem write destinations on read, so anything that could escape the
# repo (absolute, '~', '.' or '..' components) is rejected.
is_safe_rel_path() {
    local p="$1"
    [[ -n "$p" ]] || return 1
    case "$p" in
        /*|"~"*) return 1 ;;
    esac
    case "/$p/" in
        */../*|*/./*) return 1 ;;
    esac
    return 0
}
