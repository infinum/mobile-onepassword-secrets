# tests/path_utils.bats
# Unit tests for glob/folder pattern helpers: entry classification, glob→regex
# translation, matching, local expansion, and the remote-path safety gate.

setup() {
    REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
    source "$REPO_ROOT/sources/helpers/__path_utils.sh"
}

# --- is_glob_entry -----------------------------------------------------------

@test "is_glob_entry spots wildcards and folder shorthand" {
    is_glob_entry 'Vault/**/*.plist'
    is_glob_entry '*.json'
    is_glob_entry 'Keys/K?.swift'
    is_glob_entry 'Vault/Keys/'
    ! is_glob_entry 'Keys/Keys.staging.swift'
    ! is_glob_entry 'secrets.properties'
}

# --- normalize_pattern -------------------------------------------------------

@test "normalize_pattern turns a trailing slash into a recursive glob" {
    [ "$(normalize_pattern 'Vault/Keys/')" = "Vault/Keys/**" ]
    [ "$(normalize_pattern 'Vault/**')" = "Vault/**" ]
    [ "$(normalize_pattern '*.json')" = "*.json" ]
}

# --- path_matches_pattern ----------------------------------------------------

@test "star and question mark do not cross slashes" {
    path_matches_pattern 'a.json' '*.json'
    ! path_matches_pattern 'd/a.json' '*.json'
    path_matches_pattern 'Keys/a.swift' 'Keys/*.swift'
    ! path_matches_pattern 'Keys/sub/a.swift' 'Keys/*.swift'
    path_matches_pattern 'Keys/K1.swift' 'Keys/K?.swift'
    ! path_matches_pattern 'Keys/K12.swift' 'Keys/K?.swift'
    ! path_matches_pattern 'Keys/K/.swift' 'Keys/K?.swift'
}

@test "double star crosses directories, including zero of them" {
    path_matches_pattern 'Vault/a.plist' 'Vault/**/*.plist'
    path_matches_pattern 'Vault/x/y/a.plist' 'Vault/**/*.plist'
    ! path_matches_pattern 'Other/a.plist' 'Vault/**/*.plist'
    path_matches_pattern 'Vault/deep/nested/f.txt' 'Vault/**'
    path_matches_pattern 'Vault/f.txt' 'Vault/**'
    ! path_matches_pattern 'Vault' 'Vault/**'
}

@test "folder shorthand matches everything under the folder" {
    path_matches_pattern 'Vault/Keys/a.swift' 'Vault/Keys/'
    path_matches_pattern 'Vault/Keys/x/y.swift' 'Vault/Keys/'
    ! path_matches_pattern 'Vault/Other/a.swift' 'Vault/Keys/'
}

@test "regex metacharacters in patterns stay literal" {
    path_matches_pattern 'App.(dev)+[1].json' 'App.(dev)+[1].json'
    ! path_matches_pattern 'Appx(dev)+[1]xjson' 'App.(dev)+[1].json'
    path_matches_pattern 'My Keys/K 1.swift' 'My Keys/*.swift'
}

# --- expand_glob_local -------------------------------------------------------

@test "expand_glob_local lists matching files, sorted, without ./ prefix" {
    WORKDIR="$(mktemp -d)"
    cd "$WORKDIR"
    mkdir -p Vault/Keys/sub Other .git
    touch Vault/Keys/a.swift Vault/Keys/b.swift Vault/Keys/sub/c.swift
    touch Vault/Keys/notes.txt Other/d.swift .git/e.swift

    run expand_glob_local 'Vault/Keys/**/*.swift'
    [ "$status" -eq 0 ]
    [ "$output" = "Vault/Keys/a.swift
Vault/Keys/b.swift
Vault/Keys/sub/c.swift" ]

    cd /
    rm -rf "$WORKDIR"
}

@test "expand_glob_local outputs nothing when nothing matches" {
    WORKDIR="$(mktemp -d)"
    cd "$WORKDIR"
    mkdir -p Vault

    run expand_glob_local 'Vault/**/*.swift'
    [ "$status" -eq 0 ]
    [ -z "$output" ]

    cd /
    rm -rf "$WORKDIR"
}

# --- is_safe_rel_path --------------------------------------------------------

@test "is_safe_rel_path rejects traversal and absolute paths" {
    ! is_safe_rel_path '/etc/passwd'
    ! is_safe_rel_path '~/x'
    ! is_safe_rel_path '../evil.txt'
    ! is_safe_rel_path 'a/../b'
    ! is_safe_rel_path 'a/..'
    ! is_safe_rel_path 'a/./b'
    ! is_safe_rel_path ''
}

@test "is_safe_rel_path rejects a leading dash" {
    ! is_safe_rel_path '-p/evil.txt'
    ! is_safe_rel_path '--force'
    is_safe_rel_path 'a/-b/c.txt'
    is_safe_rel_path 'a-b.txt'
}

@test "is_safe_rel_path accepts ordinary repo paths" {
    is_safe_rel_path 'a..b/c.txt'
    is_safe_rel_path '.env.staging'
    is_safe_rel_path 'My Keys/K 1.swift'
    is_safe_rel_path 'Vault/Keys/a.swift'
}
