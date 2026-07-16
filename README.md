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
infinum-secrets read                  # download matching secrets into the path
infinum-secrets read <vault>          # only from one vault
infinum-secrets write [subdir]        # upload local secrets (optionally a subdir)
```

## Configuration (`secrets.config.json`)

```json
{
  "platform": "ios",
  "path": "ProjectName/SupportingFiles/Vault",
  "vaults": [
    { "name": "project-x-ios-staging", "patterns": ["*.staging.*", "*.dev.*"] },
    { "name": "project-x-ios",         "patterns": ["*.production.*"] }
  ]
}
```

| Field | Type | Meaning |
|-------|------|---------|
| `platform` | string | `ios` or `android`. |
| `path` | string | Local root directory where secret files live. |
| `vaults` | object[] | 1Password vaults. Each has a `name` and a list of glob `patterns`. |
| `vaults[].patterns` | string[] | Globs matched against a file's path **relative to `path`**. First match (in vault, then pattern, order) wins. |

A file is routed to the vault whose pattern it matches; its path relative to
`path` is used as the 1Password document title, so `read` restores it to the same
location. Patterns match on the relative path, so both `*.staging.*` and
`*/production/*.swift` work.

- `read` — for each vault, lists its documents and downloads the ones whose title
  matches that vault's patterns.
- `write [subdir]` — walks `path` (or `path/subdir`), routes each file to a vault
  by pattern, and uploads it (title = relative path).

## Development

Run from the repo without installing:

```bash
INFINUM_SECRETS_SOURCES=./sources ./infinum-secrets.sh --help
```

Run tests (requires `bats-core`: `brew install bats-core`):

```bash
bats tests/
```
