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
  CLI — `brew install --cask 1password-cli`
- [`jq`](https://jqlang.github.io/jq/) — `brew install jq`
- `bash` 3.2 or newer (the macOS system bash is fine)

## Getting started

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/infinum/mobile-onepassword-secrets/main/install.sh)"
```

The installer picks a writable directory on your `PATH` (defaulting to
`/usr/local/bin`) and drops the `app-secrets` entry point there. Update later
with `app-secrets --update`.

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
only shells out to `op` and `jq`. Point `APP_SECRETS_SOURCES` at the local
`sources/` directory to run without installing:

```bash
APP_SECRETS_SOURCES=./sources ./app-secrets.sh doctor
```

The suite uses [`bats-core`](https://github.com/bats-core/bats-core)
(`brew install bats-core`) and exercises `read`/`write`/`doctor` end-to-end
against a fake `op` on `PATH`:

```bash
bats tests/
shellcheck app-secrets.sh install.sh sources/*.sh sources/helpers/*.sh
```

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
