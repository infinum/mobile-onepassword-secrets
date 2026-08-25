#!/usr/bin/env bash
#
# Release automation for app-secrets. Covers both distribution channels:
#   - Homebrew (infinum/tap)   - primary, macOS developer machines + macOS CI
#   - npm (@infinum/app-secrets) - secondary, Linux CI without Homebrew
#
# Usage:
#   scripts/release.sh prepare <version> [--direct] [--dry-run] [--skip-tests]
#   scripts/release.sh publish           [--direct] [--dry-run]
#
# prepare  Runs the test suite (bats + shellcheck), writes <version> into
#          sources/__constants.sh and package.json, commits, pushes and opens
#          a PR (or pushes straight to main with --direct).
#          Run on main to get a release/v<version> branch, or on an existing
#          feature branch to fold the bump into that branch's PR.
#
# publish  Run on an up-to-date main once the prepare PR is merged. Tags,
#          creates the GitHub release, publishes to npm, and updates the
#          Homebrew formula in the tap via PR (or direct push with --direct).
#          Every step is skipped if already done, so it is safe to re-run.
#
# Requirements: git, gh (authenticated), npm (logged in), curl, shasum, brew,
#               bats + shellcheck for the test gate (brew install bats-core shellcheck).

set -euo pipefail

REPO_SLUG="infinum/mobile-onepassword-secrets"
MAIN_BRANCH="main"
NPM_PACKAGE="@infinum/app-secrets"
VERSION_FILE="sources/__constants.sh"
TAP_SLUG="infinum/homebrew-tap"
TAP_MAIN_BRANCH="main"
FORMULA_FILE="Formula/app-secrets.rb"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

DRY_RUN="false"
DIRECT="false"
SKIP_TESTS="false"

#################################
#            HELPERS            #
#################################

info()  { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
ok()    { printf '\033[1;32m  ✓\033[0m %s\n' "$*"; }
skip()  { printf '\033[1;33m  ↷\033[0m %s\n' "$*"; }
fail()  { printf '\033[1;31mError:\033[0m %s\n' "$*" >&2; exit 1; }

# Runs a mutating command, or just prints it under --dry-run.
run() {
    if [ "$DRY_RUN" == "true" ]; then
        printf '\033[2m  $ %s\033[0m\n' "$*"
    else
        "$@"
    fi
}

usage() {
    sed -n '2,/^$/p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
    exit "${1:-0}"
}

require_cmd() {
    command -v "$1" &> /dev/null || fail "'$1' is required but not installed."
}

current_version() {
    sed -n 's/^VERSION="\([^"]*\)"$/\1/p' "$VERSION_FILE"
}

package_version() {
    node -p "require('./package.json').version"
}

require_clean_tree() {
    [ -z "$(git status --porcelain)" ] || fail "Working tree is not clean. Commit or stash your changes first."
}

require_gh_auth() {
    gh auth status &> /dev/null || fail "GitHub CLI is not authenticated. Run 'gh auth login'."
}

require_npm_auth() {
    npm whoami &> /dev/null || fail "npm is not authenticated. Run 'npm login'."
}

# Opens a PR for <head> against <base> in <repo>, unless one is already open.
open_pr() {
    local repo="$1" base="$2" head="$3" title="$4" body="$5" existing
    existing="$(gh pr list --repo "$repo" --head "$head" --state open --json url -q '.[0].url')"
    if [ -n "$existing" ]; then
        skip "PR already open: $existing"
    else
        run gh pr create --repo "$repo" --base "$base" --head "$head" --title "$title" --body "$body"
        ok "Opened PR in $repo"
    fi
}

run_tests() {
    if [ "$SKIP_TESTS" == "true" ]; then
        skip "Tests skipped (--skip-tests)"
        return
    fi
    require_cmd bats; require_cmd shellcheck
    info "Running shellcheck"
    shellcheck app-secrets.sh sources/*.sh sources/helpers/*.sh || fail "shellcheck reported issues."
    ok "shellcheck clean"
    info "Running bats suite"
    bats tests/ || fail "Test suite failed."
    ok "Tests passed"
}

tap_dir() {
    local dir
    dir="${APP_SECRETS_TAP_DIR:-$(brew --repository "$TAP_SLUG" 2> /dev/null || true)}"
    [ -n "$dir" ] && [ -d "$dir/.git" ] || fail "Homebrew tap clone not found. Run 'brew tap infinum/tap' or set APP_SECRETS_TAP_DIR."
    echo "$dir"
}

#################################
#            PREPARE            #
#################################

prepare() {
    local version="$1"

    [[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || fail "Version must be in X.Y.Z format, got '$version'."

    require_cmd git; require_cmd gh; require_cmd node; require_cmd npm
    require_gh_auth
    require_clean_tree
    run_tests

    local current branch
    current="$(current_version)"
    [ "$current" != "$version" ] || fail "Version is already $version."
    git rev-parse -q --verify "refs/tags/v$version" &> /dev/null && fail "Tag v$version already exists."

    branch="$(git branch --show-current)"
    if [ "$branch" == "$MAIN_BRANCH" ]; then
        info "Updating $MAIN_BRANCH"
        run git pull --ff-only origin "$MAIN_BRANCH"
        if [ "$DIRECT" != "true" ]; then
            branch="release/v$version"
            info "Creating branch $branch"
            run git checkout -B "$branch"
        fi
    else
        [ "$DIRECT" != "true" ] || fail "--direct is only allowed from $MAIN_BRANCH."
        info "Adding version bump to current branch '$branch'"
    fi

    info "Bumping version $current -> $version"
    run sed -i '' "s/^VERSION=\"$current\"$/VERSION=\"$version\"/" "$VERSION_FILE"
    run npm version "$version" --no-git-tag-version --allow-same-version
    if [ "$DRY_RUN" != "true" ]; then
        [ "$(current_version)" == "$version" ] || fail "Failed to update VERSION in $VERSION_FILE."
        [ "$(package_version)" == "$version" ] || fail "Failed to update version in package.json."
    fi
    ok "$VERSION_FILE and package.json now at $version"

    info "Committing and pushing"
    run git add "$VERSION_FILE" package.json
    run git commit -q -m "Bump version to $version"
    run git push -u --force-with-lease origin "$branch"

    if [ "$DIRECT" == "true" ]; then
        ok "Pushed to $MAIN_BRANCH. Now run: scripts/release.sh publish"
        return
    fi

    info "Opening pull request"
    open_pr "$REPO_SLUG" "$MAIN_BRANCH" "$branch" "Release v$version" \
        "$(printf 'Version bump to %s.\n\nAfter merging, run `scripts/release.sh publish` from an up-to-date `%s` to tag, publish to npm and update the Homebrew formula.' "$version" "$MAIN_BRANCH")"
    echo "  Once merged, run: git checkout $MAIN_BRANCH && git pull && scripts/release.sh publish"
}

#################################
#            PUBLISH            #
#################################

publish() {
    require_cmd git; require_cmd gh; require_cmd node; require_cmd npm; require_cmd curl; require_cmd shasum; require_cmd brew
    require_gh_auth
    require_npm_auth
    require_clean_tree

    local tap version tag tarball_url head_commit pkg_version
    tap="$(tap_dir)"

    [ "$(git branch --show-current)" == "$MAIN_BRANCH" ] || fail "publish must run from $MAIN_BRANCH."
    info "Checking $MAIN_BRANCH is up to date"
    git fetch -q origin "$MAIN_BRANCH"
    head_commit="$(git rev-parse HEAD)"
    [ "$head_commit" == "$(git rev-parse "origin/$MAIN_BRANCH")" ] || fail "Local $MAIN_BRANCH differs from origin/$MAIN_BRANCH. Pull (or push) first."

    version="$(current_version)"
    [ -n "$version" ] || fail "Could not read VERSION from $VERSION_FILE."
    pkg_version="$(package_version)"
    [ "$pkg_version" == "$version" ] || fail "Version mismatch: $VERSION_FILE has $version, package.json has $pkg_version. Run 'prepare' first."
    tag="v$version"
    tarball_url="https://github.com/$REPO_SLUG/archive/refs/tags/$tag.tar.gz"
    info "Publishing $tag"

    # --- Git tag ---------------------------------------------------------
    if git rev-parse -q --verify "refs/tags/$tag" &> /dev/null; then
        [ "$(git rev-parse "$tag^{commit}")" == "$head_commit" ] || fail "Tag $tag exists but points at a different commit."
        skip "Tag $tag already exists"
    else
        run git tag -a "$tag" -m "Release $tag"
        ok "Tagged $tag"
    fi
    local tag_on_origin="false"
    git ls-remote --exit-code --tags origin "refs/tags/$tag" &> /dev/null && tag_on_origin="true"
    if [ "$tag_on_origin" == "true" ]; then
        skip "Tag $tag already on origin"
    else
        run git push origin "$tag"
        ok "Pushed tag $tag"
    fi

    # --- GitHub release --------------------------------------------------
    if gh release view "$tag" --repo "$REPO_SLUG" &> /dev/null; then
        skip "GitHub release $tag already exists"
    else
        run gh release create "$tag" --repo "$REPO_SLUG" --title "$tag" --generate-notes --verify-tag
        ok "Created GitHub release $tag"
    fi

    # --- npm -------------------------------------------------------------
    if [ -n "$(npm view "$NPM_PACKAGE@$version" version 2> /dev/null)" ]; then
        skip "$NPM_PACKAGE@$version already on npm"
    else
        run npm publish
        ok "Published $NPM_PACKAGE@$version"
    fi

    # --- Homebrew formula ------------------------------------------------
    local sha="" formula_version tap_branch tap_pr_title tap_pr_body worktree attempt
    tap_branch="app-secrets-$version"
    tap_pr_title="app-secrets $version"
    tap_pr_body="Updates the formula to [$tag](https://github.com/$REPO_SLUG/releases/tag/$tag)."

    # Check the tap's remote state, not the local clone, so re-runs and stale clones behave.
    git -C "$tap" fetch -q origin "$TAP_MAIN_BRANCH"
    formula_version="$(git -C "$tap" show "origin/$TAP_MAIN_BRANCH:$FORMULA_FILE" | sed -n 's|.*archive/refs/tags/v\([^/]*\)\.tar\.gz.*|\1|p')"
    if [ "$formula_version" == "$version" ]; then
        skip "Formula already at $version on $TAP_SLUG $TAP_MAIN_BRANCH"
        return
    fi
    if [ "$DIRECT" != "true" ] && git -C "$tap" ls-remote --exit-code --heads origin "$tap_branch" &> /dev/null; then
        skip "Branch $tap_branch already pushed to $TAP_SLUG"
        open_pr "$TAP_SLUG" "$TAP_MAIN_BRANCH" "$tap_branch" "$tap_pr_title" "$tap_pr_body"
        return
    fi

    info "Computing sha256 of $tarball_url"
    if [ "$DRY_RUN" == "true" ] && [ "$tag_on_origin" != "true" ]; then
        sha="<sha256-of-$tag-tarball>"
        skip "Tag not on origin yet, using placeholder sha in dry run"
    else
        # GitHub generates the tag tarball lazily, so it may 404 for a moment after the push.
        # curl's exit status is checked directly: with `|| true` a failed download would
        # yield the sha256 of an empty string and be accepted as valid.
        for attempt in 1 2 3 4 5; do
            if sha="$(curl -fsSL "$tarball_url" | shasum -a 256 | cut -d' ' -f1)"; then
                break
            fi
            sha=""
            echo "  tarball not available yet, retrying ($attempt/5)..."
            sleep 3
        done
        [[ "$sha" =~ ^[0-9a-f]{64}$ ]] || fail "Could not download $tarball_url."
    fi
    ok "sha256 $sha"

    worktree="$(mktemp -d)"
    info "Updating $FORMULA_FILE in $TAP_SLUG"
    run git -C "$tap" worktree add -q -B "$tap_branch" "$worktree" "origin/$TAP_MAIN_BRANCH"
    run sed -i '' \
        -e "s|archive/refs/tags/v[^/]*\.tar\.gz|archive/refs/tags/$tag.tar.gz|" \
        -e "s|^\(  sha256 \)\"[0-9a-f]*\"|\1\"$sha\"|" \
        "$worktree/$FORMULA_FILE"
    run git -C "$worktree" add "$FORMULA_FILE"
    run git -C "$worktree" commit -q -m "app-secrets $version"
    if [ "$DIRECT" == "true" ]; then
        run git -C "$worktree" push origin "HEAD:$TAP_MAIN_BRANCH"
        ok "Pushed formula update to $TAP_SLUG $TAP_MAIN_BRANCH"
    else
        run git -C "$worktree" push -u origin "$tap_branch"
        open_pr "$TAP_SLUG" "$TAP_MAIN_BRANCH" "$tap_branch" "$tap_pr_title" "$tap_pr_body"
    fi
    run git -C "$tap" worktree remove --force "$worktree"
    [ "$DRY_RUN" != "true" ] || rmdir "$worktree" 2> /dev/null || true
    run git -C "$tap" branch -D "$tap_branch"

    echo
    ok "Release $tag done."
    echo "  Homebrew users: brew update && brew upgrade app-secrets   (after the tap PR is merged)"
    echo "  npm users:      npm update -g $NPM_PACKAGE"
}

#################################
#             MAIN              #
#################################

COMMAND="${1:-}"
[ -n "$COMMAND" ] || usage 1
shift

POSITIONAL=()
while [ $# -gt 0 ]; do
    case "$1" in
        --dry-run) DRY_RUN="true" ;;
        --direct)  DIRECT="true" ;;
        --skip-tests) SKIP_TESTS="true" ;;
        -h|--help) usage ;;
        -*)        fail "Unknown option '$1'." ;;
        *)         POSITIONAL+=("$1") ;;
    esac
    shift
done

[ "$DRY_RUN" != "true" ] || info "Dry run - no changes will be made"

case "$COMMAND" in
    prepare)
        [ "${#POSITIONAL[@]}" -eq 1 ] || fail "Usage: scripts/release.sh prepare <version>"
        prepare "${POSITIONAL[0]}"
        ;;
    publish)
        [ "${#POSITIONAL[@]}" -eq 0 ] || fail "Usage: scripts/release.sh publish"
        publish
        ;;
    -h|--help) usage ;;
    *) fail "Unknown command '$COMMAND'. Use 'prepare' or 'publish'." ;;
esac
