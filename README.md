# infinum-secrets

CLI to sync project secrets between local files and 1Password vaults, driven by a
per-project `secrets.config.json`. Stack-agnostic — works for iOS, Android, or any
project that keeps secret files in the repo.

## Requirements

- [`op`](https://developer.1password.com/docs/cli/get-started/) — 1Password CLI:
  `brew install --cask 1password-cli`
- `jq`: `brew install jq`

## Install

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/infinum/mobile-onepassword-secrets/main/install.sh)"
```

Update later with `infinum-secrets --update`.

## Usage

```bash
infinum-secrets init          # scaffold secrets.config.json
infinum-secrets doctor        # check tooling, sign-in, vault access
infinum-secrets read          # download every configured file to its path
infinum-secrets read <vault>  # only one vault (its name or friendly label)
infinum-secrets write         # upload every configured file that exists locally
infinum-secrets write <vault> # only one vault
```

## Authentication

Uses your `op` session. On CI, set a
[service account token](https://developer.1password.com/docs/service-accounts/)
— `op` picks up `OP_SERVICE_ACCOUNT_TOKEN` automatically (no desktop app, no
prompts). Service accounts are read-only unless granted write access. Locally,
sign in with `op signin` (with the 1Password app integration enabled).

## Configuration (`secrets.config.json`)

```json
{
  "vaults": [
    {
      "name": "staging",
      "vault": "project-x-android-staging",
      "files": ["secrets-staging.properties"]
    },
    {
      "name": "production",
      "vault": "project-x-android",
      "files": ["secrets.properties"]
    }
  ]
}
```

| Field | Type | Meaning |
|-------|------|---------|
| `vaults` | object[] | The 1Password vaults, each owning a set of files. |
| `vaults[].vault` | string | The 1Password vault name. |
| `vaults[].name` | string | Optional friendly label (for `read <label>` / `write <label>`). |
| `vaults[].files` | string[] | File paths (relative to the repo/CWD) that live in this vault. |

- Each entry in `files` is a real file path — put the folder in the path; files can
  live anywhere (no single shared root is assumed).
- The **1Password document title is the file name** (e.g. `secrets-staging.properties`,
  `Keys.staging.swift`).
- `read` fetches each configured file's document (by title) into that file's path,
  creating folders as needed. `write` uploads each configured file that exists
  locally. Both accept an optional vault (name or label) to scope to.

Example for a nested layout (e.g. iOS):

```json
{
  "vaults": [
    { "name": "staging", "vault": "project-x-ios-staging",
      "files": ["ProjectName/SupportingFiles/Vault/Keys/Keys.staging.swift"] },
    { "name": "production", "vault": "project-x-ios",
      "files": ["ProjectName/SupportingFiles/Vault/Keys/Keys.production.swift"] }
  ]
}
```

## Development

Run from the repo without installing:

```bash
INFINUM_SECRETS_SOURCES=./sources ./infinum-secrets.sh --help
```

Run tests (requires `bats-core`: `brew install bats-core`):

```bash
bats tests/
```
