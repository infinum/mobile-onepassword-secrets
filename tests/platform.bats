# tests/platform.bats
setup() {
    REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
    source "$REPO_ROOT/sources/helpers/__platform.sh"
}

@test "platform_default_path returns ios path" {
    run platform_default_path ios
    [ "$status" -eq 0 ]
    [ "$output" = "ProjectName/SupportingFiles/Vault" ]
}

@test "platform_default_path returns android path" {
    run platform_default_path android
    [ "$output" = "app/src/main/secrets" ]
}

@test "platform_validate accepts ios" {
    run platform_validate ios
    [ "$status" -eq 0 ]
}

@test "platform_validate rejects android as not implemented" {
    run platform_validate android
    [ "$status" -ne 0 ]
    [[ "$output" == *"not yet implemented"* ]]
}

@test "platform_validate rejects unknown platform" {
    run platform_validate windows
    [ "$status" -ne 0 ]
    [[ "$output" == *"unknown platform"* ]]
}
