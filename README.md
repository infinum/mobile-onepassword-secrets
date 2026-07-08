# infinum-secrets

CLI to sync project secrets between a local directory and 1Password vaults,
driven by a per-project `secrets.config.json`. iOS is supported today; Android
is scaffolded.

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
infinum-secrets init --platform ios   # scaffold secrets.config.json
infinum-secrets doctor                # check tooling, sign-in, vault access
infinum-secrets read                  # download secrets into the configured path
infinum-secrets read <vault>          # only from one vault
infinum-secrets write <dir>           # upload a local dir's secrets
```

## Configuration (`secrets.config.json`)

| Field | Type | Meaning |
|-------|------|---------|
| `platform` | string | `ios` or `android`. |
| `path` | string | Local dir where secret files live. |
| `environments` | string[] | Known envs; drives filename validation and `*` expansion. |
| `vaults` | string[] | 1Password vaults for this project. |
| `files` | object[] | `{ name, environments }`; `environments: ["*"]` = all. |
| `fileVaults` | object[] | `{ pattern, vault }`; first glob match wins. |

Files are named `<base>.<env>.<ext>` (e.g. `Keys.production.swift`).

## Development

Run from the repo without installing:

```bash
INFINUM_SECRETS_SOURCES=./sources ./infinum-secrets.sh --help
```

Run tests (requires `bats-core`: `brew install bats-core`):

```bash
bats tests/
```
