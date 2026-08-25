# app-secrets

`app-secrets` syncs project secrets between local files and
[1Password](https://1password.com) vaults, driven by a per-project
`.secrets.config.json`. It wraps the
[1Password CLI (`op`)](https://developer.1password.com/docs/cli/) so pulling and
pushing secret files is one command instead of a series of `op document` calls.

It is **stack-agnostic** — iOS, Android, Flutter, React Native and anything else
that keeps secret files in the repo are just different file paths in the same
config. A vault owns a set of files, and `read`/`write` sync them.

## Requirements

- [`op`](https://developer.1password.com/docs/cli/get-started/), the 1Password
  CLI. It is cask-only, so the Homebrew formula cannot pull it in for you:
  `brew install --cask 1password-cli` on macOS, or follow 1Password's
  [Linux install guide](https://developer.1password.com/docs/cli/get-started/)
  on CI.
- [`jq`](https://jqlang.github.io/jq/) — comes with the Homebrew formula. With
  the npm package or a checkout, install it yourself (`brew install jq`,
  `apt-get install jq`, ...).
- `bash` 3.2 or newer (the macOS system bash is fine)

## Getting started

First install `op` (the 1Password CLI) — it can't be pulled in automatically
because it's only distributed as a Homebrew
[cask](https://formulae.brew.sh/cask/1password-cli), and a formula can't
depend on one:

```bash
brew install --cask 1password-cli
```

### Installation

#### Homebrew

This script is distributed via [Homebrew](https://brew.sh) through Infinum's tap:

```bash
brew install infinum/tap/app-secrets
```

Homebrew 6.0+ requires trusting non-official taps before installing from them,
so if that command fails or prompts you to trust the tap, tap and trust it
explicitly first, then install:

```bash
brew tap infinum/tap
brew trust infinum/tap
brew install app-secrets
```

This also installs `jq` if you don't already have it.

#### npm

The same script is also published to npm as
[`@infinum/app-secrets`](https://www.npmjs.com/package/@infinum/app-secrets):

```bash
npm install -g @infinum/app-secrets
```

Unlike the formula, the npm package does not install `jq` or `op` — install
both first (see [Requirements](#requirements)), then run `app-secrets doctor`
to confirm the tooling is in place.

#### Update

Script can be updated by running:
```bash
brew upgrade app-secrets
# or, for npm installations
npm update -g @infinum/app-secrets
```

## Usage

```bash
app-secrets init           # scaffold .secrets.config.json and open it in your editor
app-secrets doctor         # check tooling, sign-in status, and vault access
app-secrets read           # download every configured file to its path
app-secrets write          # upload every configured file that exists locally
app-secrets read <vault>   # restrict to one vault (its name or friendly label)
app-secrets --help         # full help
```

`read` fetches each configured file's document into that file's path, creating
folders as needed. `write` uploads each configured file that exists locally,
previewing the change and asking for confirmation when interactive; automation
proceeds without prompting. Neither aborts on the first problem — they finish
the run and report it in the exit status, so **CI can rely on `$?`**: `0` means
every configured file is in sync.

## Configuration

Each project keeps a `.secrets.config.json` in its root, created by
`app-secrets init`. The schema is **vault-centric**: each vault owns the list of
local files that belong to it.

```json
{
  "vaults": [
    {
      "name": "staging",
      "vault": "project-myapp-ios-staging",
      "files": ["MyApp/Vault/Keys/Keys.staging.swift", "Certs/"]
    },
    {
      "name": "production",
      "vault": "project-myapp-ios",
      "files": ["MyApp/Vault/Keys/Keys.production.swift"]
    }
  ]
}
```

| Field | Type | Meaning |
|-------|------|---------|
| `vaults[].vault` | string | The 1Password vault name (required). |
| `vaults[].name` | string | Optional friendly label; `read <label>` / `write <label>` resolve it. |
| `vaults[].files` | string[] | Repo-relative paths (or glob patterns) that live in this vault (required, non-empty). |

The **document title is the file name**, and the full repo-relative path is
stamped on the item as a `path` field — which is how two files that share a name
in different folders stay apart. `files` entries can also be glob patterns
(`Vault/**/*.staging.*`) or folder shorthand (`Certs/`).

See the [wiki](https://github.com/infinum/mobile-onepassword-secrets/wiki) for
config layouts, the full pattern dialect and its safety rules, exit-code
details, and the internals.

## Authentication

- **Locally**, `app-secrets` uses your `op` session. Sign in through the
  1Password desktop app with CLI integration enabled
  (**Settings → Developer → Integrate with 1Password CLI**).
- **On CI**, set a
  [service account token](https://developer.1password.com/docs/service-accounts/).
  `op` picks up `OP_SERVICE_ACCOUNT_TOKEN` automatically — no desktop app, no
  prompts.

Run `app-secrets doctor` to confirm the tooling is installed, that you're signed
in, and which vaults you can read and write.

## Development

Plain `bash` (3.2+, so it runs on the stock macOS shell) with no build step; it
only shells out to `op` and `jq`. The entry point picks up the `sources/`
directory next to it, so a checkout runs without installing:

```bash
./app-secrets.sh doctor
```

Set `APP_SECRETS_SOURCES` to point it at a different `sources/` directory
(the Homebrew wrapper and the tests do this).

The suite uses [`bats-core`](https://github.com/bats-core/bats-core)
(`brew install bats-core`) and exercises `read`/`write`/`doctor` end-to-end
against a fake `op` on `PATH`:

```bash
bats tests/
shellcheck app-secrets.sh sources/*.sh sources/helpers/*.sh
```

## Releasing

Releases are cut with `scripts/release.sh`, which keeps the version in
`sources/__constants.sh` and `package.json` in sync and publishes to both
Homebrew and npm. The version is typed exactly once:

```bash
scripts/release.sh prepare 1.1.0   # runs bats + shellcheck, bumps the version, opens a PR
# ... merge the PR ...
git checkout main && git pull
scripts/release.sh publish         # tags, creates the GitHub release, publishes to npm, opens the tap PR
```

Both commands accept `--dry-run` (print what would happen) and `--direct` (push
to the protected branch instead of opening a PR, for maintainers with bypass
rights); `prepare` also accepts `--skip-tests`. `publish` skips any step that
has already been done, so it can be re-run safely after a failure.
Requirements: `gh` and `npm` authenticated, `bats-core` and `shellcheck`
installed, and the `infinum/tap` tap installed locally.

## License

Licensed under the [Apache License, Version 2.0](LICENSE).

## Credits

Maintained and sponsored by [Infinum](https://infinum.com).

<div align="center">
    <a href='https://infinum.com'>
    <picture>
        <source srcset="https://assets.infinum.com/brand/logo/static/white.svg" media="(prefers-color-scheme: dark)">
        <img src="https://assets.infinum.com/brand/logo/static/default.svg">
    </picture>
    </a>
</div>
