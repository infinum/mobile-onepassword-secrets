# app-secrets

## Description

`app-secrets` is a small command-line tool that syncs project secrets
between local files and [1Password](https://1password.com) vaults, driven by a
per-project `.secrets.config.json`. It wraps the [1Password CLI (`op`)](https://developer.1password.com/docs/cli/)
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
* [Roadmap](#roadmap)
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
app-secrets init          # scaffold .secrets.config.json and open it in your editor
app-secrets init --no-open # scaffold without opening
app-secrets doctor        # check tooling, sign-in status, and vault access
app-secrets read          # download every configured file to its path
app-secrets read <vault>  # restrict to one vault (its name or friendly label)
app-secrets write         # upload every configured file that exists locally
app-secrets write <vault> # restrict to one vault
app-secrets --version     # print the version
app-secrets --help        # full help
```

- `init` writes the template and opens it in your editor. It prefers
  `$APP_SECRETS_OPENER`, then `$VISUAL` / `$EDITOR`, then `open` (macOS) /
  `xdg-open` (Linux). Pass `--no-open` to skip opening (opening is also skipped
  when non-interactive, e.g. CI).
- `read` fetches each configured file's document (matched by title and the
  `path` field, then fetched by item id) from its vault into that file's path,
  creating folders as needed. Pattern entries download every document whose
  stored path matches. A vault you can't access doesn't abort the other
  vaults, but it does fail the run.
- `write` uploads each configured file that exists locally (create if the
  document is absent, edit if present). Pattern entries expand against the
  local tree first. Missing local files are skipped. It previews the upload
  and asks for confirmation when run interactively; automation (CI) proceeds
  without prompting.
- Both accept an optional vault argument (vault name or friendly label) to scope
  the operation to a single vault.

### Exit codes

`read` and `write` keep going after a problem so one bad entry doesn't hide the
rest, then report it in the exit status. **CI can rely on `$?`**: a green step
means every configured file is in sync.

| Exit | Meaning |
|------|---------|
| `0` | Everything configured was synced. |
| `1` | The run finished but something is out of sync, or it couldn't start (missing tooling, no session, bad config, unknown vault argument). |

Failing the run: a document that can't be fetched, uploaded, resolved (duplicate
items), or listed; a configured file with no document in the vault; a vault you
can't access; a stored path rejected by the safety gate; an upload whose `path`
field couldn't be stamped.

Not failing the run: a pattern that matches nothing (on either side — patterns
describe "whatever is there"), and a configured file that doesn't exist locally
when you `write`.

## Configuration

Each project keeps a `.secrets.config.json` (created by `app-secrets init`)
in its root. The schema is **vault-centric**: each vault owns the list of local
files that belong to it.

| Field | Type | Meaning |
|-------|------|---------|
| `vaults` | object[] | The 1Password vaults, each owning a set of files. |
| `vaults[].vault` | string | The 1Password vault name (required). |
| `vaults[].name` | string | Optional friendly label; `read <label>` / `write <label>` resolve it. |
| `vaults[].files` | string[] | File paths, relative to the repo root, that live in this vault (required, non-empty). |

The **1Password document title is the file name** (including extension). For
example `App/Secrets/Keys.staging.swift` is stored as a document titled
`Keys.staging.swift`. The full repo-relative path is stored on the item as a
custom **`path` text field**: `write` stamps it automatically, and both
commands use it to tell apart files that share a name but live in different
folders — a target-based layout such as `Staging/GoogleService-Info.plist` and
`Production/GoogleService-Info.plist` maps to two documents with the same
title in one vault, disambiguated by their `path` fields. A document without
the field (for example one created by hand in 1Password) is matched by title
alone as long as that title is unique in the vault, and gets stamped on the
next `write`. Renaming or moving a file makes `write` create a new document —
archive the old one in 1Password manually.

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

### Glob / folder patterns

Besides literal paths, `files` entries can be patterns:

| Pattern | Meaning |
|---------|---------|
| `*` | Any characters within one path component (never crosses `/`). |
| `?` | One character within a component. |
| `**` | Any characters across directories; `**/` matches zero or more whole directories. |
| `dir/` | Trailing slash is folder shorthand for `dir/**` — everything under `dir`, recursively. |

```json
{
  "vaults": [
    {
      "name": "staging",
      "vault": "project-myapp-ios-staging",
      "files": [
        "MyApp/SupportingFiles/Vault/**/*.staging.*",
        "Certs/"
      ]
    }
  ]
}
```

On `write`, patterns expand against the local tree and every match is uploaded
(and stamped with its path). On `read`, patterns match the `path` fields stored
on the vault's documents, and every hit is downloaded to its stamped path —
documents without the field are invisible to patterns, so run `write` once
before relying on pattern `read`. When a literal entry and a pattern overlap,
the file syncs once. Regex metacharacters in patterns are treated literally,
and stored paths that would escape the repo (absolute, `..`, leading `-`) are
refused on `read`. Note that `**` crosses directories wherever it appears —
`a**b` matches `a/x/b` — unlike gitignore, where a non-boundary `**` degrades
to `*`.

#### Typical setups

Depending on how a project lays out its secrets, glob handling enables a few
common configuration styles:

- **One secrets folder per environment vault.** Each vault owns the whole
  folder via the trailing-slash shorthand, and new files sync without touching
  the config:

  ```json
  "files": ["MyApp/SupportingFiles/Vault/"]
  ```

- **Shared tree, environment picked by suffix.** Both environments keep files
  in the same folders; each vault selects its own by name:

  ```json
  "files": ["MyApp/Vault/**/*.staging.*"]     // staging vault
  "files": ["MyApp/Vault/**/*.production.*"]  // production vault
  ```

- **Target-based folders with identical file names.** Folder shorthand per
  vault; the stored `path` field keeps the same-named documents apart:

  ```json
  "files": ["Staging/"]      // e.g. Staging/GoogleService-Info.plist
  "files": ["Production/"]   // e.g. Production/GoogleService-Info.plist
  ```

- **One file type, wherever it lives.** Scope by extension, optionally under a
  subtree:

  ```json
  "files": ["**/*.xcconfig", "Certs/**/*.pem"]
  ```

- **Literal anchors plus a catch-all.** Must-have files stay explicit (so a
  missing one is reported by name), the folder pattern picks up the rest — an
  overlap syncs once:

  ```json
  "files": ["Keys/Keys.swift", "Keys/"]
  ```

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
├── __init.sh             # __init   — scaffold .secrets.config.json
├── __read.sh             # __read   — download files
├── __write.sh            # __write  — upload files
├── __doctor.sh           # __doctor — diagnostics
├── __auto_update.sh      # __script_auto_update — powers --update
└── helpers/
    ├── __config.sh       # load + parse .secrets.config.json (via jq) into bash vars
    ├── __op_utils.sh     # op/jq checks, sign-in/service-account, vault access,
    │                     # path-field item resolution
    └── __path_utils.sh   # glob/folder pattern translation + path safety gate
tests/                    # bats-core suite
└── helpers/              # stateful fake `op` shim + shared bats setup
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
>
> **Path handling.** Everything is line-based: file names containing newlines,
> tabs, or backslashes are out of scope. Spaces are fine.

## Roadmap

Planned and proposed improvements — contributions welcome.

**Next up**

- [x] **Disambiguate same-named files in one vault.** The 1Password document title
  is the file name, so two files that share a name but live in different
  folders — a target-based layout, e.g. `Staging/GoogleService-Info.plist` and
  `Production/GoogleService-Info.plist` — used to collide when they belong to the
  same vault. Each file's repo-relative path is now stored on the 1Password item
  as a custom `path` field and matched instead of the title alone.
- [x] **Glob / folder patterns in `files`.** With the path stored on the item,
  `read` can reconstruct each file's destination, so `files` accepts globs
  (e.g. `Vault/**/*.staging.*`) and folder shorthand (`Certs/`) — expanded
  against the local tree on `write` and matched against stored `path` fields
  on `read`.

**Nice to have**

- [ ] **Homebrew formula** declaring `op` + `jq` as dependencies (replaces the curl
  installer and the runtime presence checks).
- [ ] **Migration helper** for projects moving off the old Vault workflow — read the
  existing vault config and generate a `.secrets.config.json`. Likely an agent
  prompt/skill rather than a bundled script.

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
