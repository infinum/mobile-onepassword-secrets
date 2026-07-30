# app-secrets

<!--
    This is the status area for the project.
    Add project badges (if needed) to this part of the file.
-->

## Description

`app-secrets` is a small command-line tool that syncs project secrets
between local files and [1Password](https://1password.com) vaults, driven by a
per-project `secrets.config.json`. It wraps the [1Password CLI (`op`)](https://developer.1password.com/docs/cli/)
so that pulling and pushing secret files is a single command instead of a series
of manual `op document` invocations.

It is **stack-agnostic**: iOS, Android, Flutter, React Native, or any project
that keeps secret files in the repo are just different file paths in the same
config. There is no platform concept and no per-stack code — a vault owns a set
of files, and `read`/`write` sync them.

## Table of contents

* [Requirements](#requirements)
* [Getting started](#getting-started)
* [Usage](#usage)
* [Configuration](#configuration)
* [Authentication](#authentication)
* [Development](#development)
* [Credits](#credits)

## Requirements

- [`op`](https://developer.1password.com/docs/cli/get-started/) — the 1Password CLI:

    ```bash
    brew install --cask 1password-cli
    ```

- [`jq`](https://jqlang.github.io/jq/) — used to parse the JSON config:

    ```bash
    brew install jq
    ```

- `bash` 3.2 or newer (the macOS system bash is fine).

## Getting started

Install globally with the curl-pipe-to-bash installer:

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/infinum/mobile-onepassword-secrets/main/install.sh)"
```

The installer picks a writable directory on your `PATH` (defaulting to
`/usr/local/bin`) and drops the `app-secrets` entry point there. Update to
the latest version at any time with:

```bash
app-secrets --update
```

## Usage

```bash
app-secrets init          # scaffold a secrets.config.json in the current directory
app-secrets doctor        # check tooling, sign-in status, and vault access
app-secrets read          # download every configured file to its path
app-secrets read <vault>  # restrict to one vault (its name or friendly label)
app-secrets write         # upload every configured file that exists locally
app-secrets write <vault> # restrict to one vault
app-secrets --version     # print the version
app-secrets --help        # full help
```

- `read` fetches each configured file's document (by title) from its vault into
  that file's path, creating folders as needed. Vaults you can't access are
  skipped rather than failing the whole run.
- `write` uploads each configured file that exists locally (create if the
  document is absent, edit if present). Missing local files are skipped. It
  previews the upload and asks for confirmation when run interactively;
  automation (CI) proceeds without prompting.
- Both accept an optional vault argument (vault name or friendly label) to scope
  the operation to a single vault.

## Configuration

Each project keeps a `secrets.config.json` (created by `app-secrets init`)
in its root. The schema is **vault-centric**: each vault owns the list of local
files that belong to it.

| Field | Type | Meaning |
|-------|------|---------|
| `vaults` | object[] | The 1Password vaults, each owning a set of files. |
| `vaults[].vault` | string | The 1Password vault name (required). |
| `vaults[].name` | string | Optional friendly label; `read <label>` / `write <label>` resolve it. |
| `vaults[].files` | string[] | File paths, relative to the repo root, that live in this vault (required, non-empty). |

The **1Password document title is the file name** (including extension). The
folder part of a path is never stored in 1Password — it only decides where the
file lands locally. For example `App/Secrets/Keys.staging.swift` is stored as a
document titled `Keys.staging.swift`.

### The config depends on your folder structure

Because each `files` entry is a full relative path, the config adapts to how a
project lays out its secrets.

**Flat layout** — files sit in the repo root (typical for Android):

```json
{
  "vaults": [
    {
      "name": "staging",
      "vault": "project-myapp-android-staging",
      "files": ["secrets-staging.properties"]
    },
    {
      "name": "production",
      "vault": "project-myapp-android",
      "files": ["secrets.properties"]
    }
  ]
}
```

**Nested layout** — secrets grouped under a folder (typical for iOS):

```json
{
  "vaults": [
    {
      "name": "staging",
      "vault": "project-myapp-ios-staging",
      "files": ["MyApp/SupportingFiles/Vault/Keys/Keys.staging.swift"]
    },
    {
      "name": "production",
      "vault": "project-myapp-ios",
      "files": ["MyApp/SupportingFiles/Vault/Keys/Keys.production.swift"]
    }
  ]
}
```

**Multiple files per vault, across different folders** — list every file
explicitly. Files that belong to the same environment go under the same vault,
even if they live in different directories:

```json
{
  "vaults": [
    {
      "name": "staging",
      "vault": "project-myapp-ios-staging",
      "files": [
        "MyApp/SupportingFiles/Vault/Keys/Keys.staging.swift",
        "MyApp/SupportingFiles/Vault/GoogleService/GoogleService-Info.staging.plist",
        "MyApp/SupportingFiles/Vault/AppConfig/AppConfig.staging.json"
      ]
    },
    {
      "name": "production",
      "vault": "project-myapp-ios",
      "files": [
        "MyApp/SupportingFiles/Vault/Keys/Keys.production.swift",
        "MyApp/SupportingFiles/Vault/GoogleService/GoogleService-Info.production.plist",
        "MyApp/SupportingFiles/Vault/AppConfig/AppConfig.production.json"
      ]
    }
  ]
}
```

> **Globbing / wildcards are not supported (for now).** Every file must be listed
> explicitly with its full relative path — a pattern such as
> `Vault/**/*.staging.*` will **not** expand. The reason is on `read`: a glob is
> a set of matches with no single destination, and since the document title is
> the file name (not the full path), the tool can't reconstruct where each
> matched document should be written. When you add a new secret file, add its
> path to the relevant vault's `files` array.

## Authentication

- **Locally**, `app-secrets` uses your `op` session. Sign in through the
  1Password desktop app with CLI integration enabled
  (**Settings → Developer → Integrate with 1Password CLI**); `op` prompts on its
  first call, exactly as `op document get` does on its own.
- **On CI**, set a
  [service account token](https://developer.1password.com/docs/service-accounts/).
  `op` picks up `OP_SERVICE_ACCOUNT_TOKEN` automatically — no desktop app, no
  prompts. Service accounts are read-only unless granted write access; `op`
  enforces this on the actual write.

Run `app-secrets doctor` to confirm `op`/`jq` are installed, that you're
signed in, and which vaults you can read and write.

## Development

The tool is plain `bash` (3.2+ compatible, so it runs on the stock macOS shell)
with no build step. It only shells out to `op` and `jq`.

### Run from a checkout

Point `APP_SECRETS_SOURCES` at the local `sources/` directory to run the
entry point without installing:

```bash
APP_SECRETS_SOURCES=./sources ./app-secrets.sh --help
APP_SECRETS_SOURCES=./sources ./app-secrets.sh doctor
```

### Layout

```
app-secrets.sh        # entry point: sources the libraries, dispatches on $1
install.sh                # curl-pipe-to-bash installer
sources/
├── __constants.sh        # VERSION, CLI name, config file name
├── __help.sh             # __help
├── __init.sh             # __init   — scaffold secrets.config.json
├── __read.sh             # __read   — download files
├── __write.sh            # __write  — upload files
├── __doctor.sh           # __doctor — diagnostics
├── __auto_update.sh      # __script_auto_update — powers --update
└── helpers/
    ├── __config.sh       # load + parse secrets.config.json (via jq) into bash vars
    └── __op_utils.sh     # op/jq checks, sign-in/service-account, vault access
tests/                    # bats-core suite + fake `op` shim
```

The entry point glob-sources `sources/helpers/*.sh` then `sources/*.sh`, so every
file must be side-effect-free on source (define functions, run nothing). It then
dispatches the first argument to the matching `__<command>` function.

### Add a subcommand

1. Create `sources/__foo.sh` defining a `__foo` function (mirror an existing one).
   Keep sourcing side-effect-free and initialize arrays as `local -a x=()`.
2. Wire `foo` into the dispatch `case` in `app-secrets.sh`, and add a line to
   `__help`.
3. Add a bats test under `tests/` — use the fake `op` shim (see `tests/op_flow.bats`)
   so nothing touches a real 1Password account.

### Tests and linting

The suite uses [`bats-core`](https://github.com/bats-core/bats-core)
(`brew install bats-core`) and exercises `read`/`write`/`doctor` end-to-end
against a fake `op` on `PATH`:

```bash
bats tests/
shellcheck app-secrets.sh install.sh sources/*.sh sources/helpers/*.sh
```

> **bash 3.2.** macOS ships bash 3.2, so avoid `mapfile`/`readarray`, `${var,,}`,
> and unguarded empty-array expansions. Guard arrays with `"${arr[@]+"${arr[@]}"}"`
> and initialize them as `local -a x=()`.

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
