# `infinum-secrets` CLI — Design

**Date:** 2026-06-01
**Status:** Approved (pending spec review)

## Summary

Wrap the existing 1Password bash scripts (`ios/.onepassword/{config,utils,read,write}.sh`)
into an installable CLI named `infinum-secrets`, modeled on
[`infinum/app-deploy-script`](https://github.com/infinum/app-deploy-script).

The name is org-namespaced to avoid PATH/alias collisions with the generic word
`secrets` (e.g. AWS `git-secrets`, dev aliases).

A single entry point (`infinum-secrets`) dispatches subcommands (`read`, `write`,
`init`, `doctor`, plus `--version` / `--update` / `--help`). The tool is installed globally
via a curl-pipe-to-bash installer; each consuming project holds only a JSON config
file. Read/write logic is shared and generic; platform differences (iOS vs Android)
are expressed through the config `platform` field and a thin platform hook, not
duplicated scripts.

## Goals

- One installable command with app-deploy-style subcommand structure.
- Generic, shared read/write logic — no per-platform duplication.
- Platform (iOS / Android) declared in project config; tool adapts paths/naming.
- Zero per-project script copying — projects carry only config.
- iOS fully working; Android scaffolded (seam in place, branch stubbed).

## Non-Goals

- Full Android implementation (scaffolding only this iteration).
- Replacing the `op` (1Password CLI) or `jq` dependencies.
- Signed/pinned-release auto-update verification (noted as future improvement).

## Dependencies

- `op` — 1Password CLI (`brew install --cask 1password-cli`)
- `jq` — JSON processor (`brew install jq`), now also used to parse config
- `git` — used by installer / `--update`
- bash 3.2+ (macOS system bash compatible — current scripts already are)

## Repository Layout

```
mobile-onepassword-secrets/
├── install.sh                  # curl target: clone tmp + copy + chmod
├── infinum-secrets.sh          # entry point → installs as /usr/local/bin/infinum-secrets
├── sources/
│   ├── __constants.sh          # VERSION, install paths, source dir
│   ├── __help.sh               # __help (heredoc)
│   ├── __init.sh               # __init — scaffold JSON config
│   ├── __read.sh               # __read — generic read (from ios/read.sh)
│   ├── __write.sh              # __write — generic write (from ios/write.sh)
│   ├── __doctor.sh             # __doctor — diagnostics
│   ├── __auto_update.sh        # __script_auto_update — --update
│   ├── secrets.config.json     # config template copied by init
│   └── helpers/
│       ├── __op_utils.sh       # op/jq checks, vault access (from ios/utils.sh)
│       ├── __config.sh         # load + parse JSON config → bash vars/arrays
│       └── __platform.sh       # platform hook: default path/name pattern per platform
├── README.md
├── LICENSE
└── .github/
```

The existing `ios/.onepassword/*` scripts are refactored into `sources/` and removed
as standalone copies. `config.sh` becomes the JSON config + `__config.sh` parser;
`utils.sh` becomes `helpers/__op_utils.sh`; `read.sh`/`write.sh` become
`sources/__read.sh`/`sources/__write.sh` with config loaded from JSON.

## Installer

Curl-pipe-to-bash, mirroring app-deploy:

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/infinum/mobile-onepassword-secrets/main/install.sh)"
```

`install.sh`:
1. `git clone --quiet <repo> .infinum_secrets_tmp`
2. `cat .infinum_secrets_tmp/infinum-secrets.sh > <bindir>/infinum-secrets`
3. `cp -a .infinum_secrets_tmp/sources/. <bindir>/.infinum-secrets-sources/`
4. `chmod +rx` on entry + sources
5. `trap "rm -rf .infinum_secrets_tmp" EXIT`
6. Prompt `Do you want to proceed? [y/n]` unless `--silent`.

**Install location:** default `/usr/local/bin`. Installer checks writability; if not
writable, it prints the `sudo` form or falls back to a user-writable dir on PATH.
(`/usr/local/bin` is not writable without sudo on some macOS setups.)

## Entry Point & Dispatch

`infinum-secrets.sh` sources its libraries, then dispatches on `$1` (if/elif chain,
matching app-deploy):

| Arg | Action |
|-----|--------|
| `-h` / `--help` | `__help` |
| `-v` / `--version` | `echo "infinum-secrets $VERSION"` |
| `--update` | `__script_auto_update` |
| `init` | `__init "$@"` |
| `read` | `__read "$@"` |
| `write` | `__write "$@"` |
| `doctor` (alias `status`) | `__doctor` |
| _other / empty_ | "Unsupported command" + help hint |

## Configuration

JSON file `secrets.config.json` in the project root, created by `infinum-secrets init`,
parsed with `jq`.

```json
{
  "platform": "ios",
  "path": "ProjectName/SupportingFiles/Vault",
  "environments": ["production", "staging"],
  "vaults": ["project-projectname-ios", "project-projectname-ios-staging"],
  "files": [
    { "name": "Keys.swift", "environments": ["*"] }
  ],
  "fileVaults": [
    { "pattern": "*.staging.*",    "vault": "project-projectname-ios-staging" },
    { "pattern": "*.production.*", "vault": "project-projectname-ios" }
  ]
}
```

### Field reference

| Field | Type | Meaning |
|-------|------|---------|
| `platform` | string | `ios` or `android`. Selects defaults + platform hook. |
| `path` | string | Local dir where secret files live. |
| `environments` | string[] | Known envs; drives filename validation + `*` expansion. |
| `vaults` | string[] | 1Password vaults for this project. |
| `files` | object[] | `{ name, environments }`. `environments: ["*"]` = all. |
| `fileVaults` | object[] | `{ pattern, vault }`. First glob match wins. |

### Parsing (`helpers/__config.sh`)

`__config.sh` locates `secrets.config.json` (project root / cwd), validates it is
valid JSON with required keys, and converts it into the same bash variables the
current scripts already consume:

- `path` → string var
- `environments` → bash array
- `vaults` → bash array
- `files` → bash array of `"name:env1,env2"` (or `"name:*"`) strings
- `file_vaults` → bash array of `"pattern:vault"` strings

This keeps `__read`/`__write`/`__op_utils` logic ~unchanged from today's scripts —
only the config source changes (JSON-via-jq instead of sourcing `config.sh`).

Missing config → error pointing user to `infinum-secrets init`.

## Shared Logic + Platform Hook

One generic `__read` and `__write`. The `platform` field drives `helpers/__platform.sh`,
which supplies platform-specific defaults/behavior where it genuinely differs:

- Default `path` suggestion (used by `init`).
- Filename pattern / parsing (iOS: `<base>.<env>.<ext>`).
- Any structure-specific branch.

iOS path is implemented (matches current scripts). Android is a stub:
`__platform.sh` has an `android` branch that currently errors with
"Android support not yet implemented" so the seam exists without fake behavior.

## Commands

### `init`
Writes `secrets.config.json` from the template, pre-filling platform-aware defaults
(`path`, naming). Refuses to overwrite an existing config (requires explicit
`--force`). Prints next steps.

### `read [vault]`
Behavior from current `read.sh`: downloads `<base>.<env>.<ext>` for each configured
file/env into `path`, resolving vault per `fileVaults`. Optional `vault` arg filters
to one vault (case-insensitive). Skips files where user lacks vault access. Config
loaded from JSON.

### `write [dir]`
Behavior from current `write.sh`: uploads files from `path/<dir>` to mapped vaults,
validating filenames against `environments`, checking write access, previewing, and
confirming before upload. `dir` optional (interactive prompt if omitted). Config
loaded from JSON.

### `doctor` (alias `status`)
Diagnostics:
- `op` installed? `jq` installed?
- `op` signed in? (`op user get --me`)
- `secrets.config.json` present, valid JSON, required keys present?
- Per-vault read + write access table (reuses `print_vault_access`).
Exits non-zero if a hard prerequisite is missing.

### `--version`
Prints `secrets $VERSION` from `__constants.sh`.

### `--update`
Re-runs the installer flow (clone + overwrite entry + sources). Pulls `main`.
_Future improvement:_ pin to a release tag + integrity check before overwriting a
secrets-handling tool.

### `--help` / `-h`
Single heredoc: usage, description, commands, examples.

## Error Handling

- `set -e` in entry + subcommand scripts (as today).
- Missing `op`/`jq` → clear install instructions, non-zero exit (in `__op_utils.sh`
  + surfaced by `doctor`).
- Missing/invalid config → message + `infinum-secrets init` hint.
- No vault access → graceful per-file skip with `[!]` notice (already present).
- Filename failing env validation on write → hard error with the rule (already present).

## Versioning

`VERSION` constant in `__constants.sh`, surfaced via `--version`. `--update` re-clones
latest `main`. Workflow/config-format changes (if any) versioned separately later if
needed.

## Migration of Existing Scripts

| Today | Becomes |
|-------|---------|
| `ios/.onepassword/config.sh` | `secrets.config.json` template + `helpers/__config.sh` parser |
| `ios/.onepassword/utils.sh` | `sources/helpers/__op_utils.sh` |
| `ios/.onepassword/read.sh` | `sources/__read.sh` (`__read` function) |
| `ios/.onepassword/write.sh` | `sources/__write.sh` (`__write` function) |

Logic preserved; entry/exit reshaped from standalone `main "$@"` scripts into sourced
`__<command>` functions, config from JSON.

## Testing

- Manual: `infinum-secrets init` → edit config → `infinum-secrets doctor` →
  `infinum-secrets read` → `infinum-secrets write` against a test vault.
- Where feasible, factor pure helpers (glob matching `get_vault_for_file`,
  `match_environment`, JSON→array parsing) so they can be exercised with
  [bats](https://github.com/bats-core/bats-core) or simple assertion scripts.
- Lint with `shellcheck` (already clean in current scripts).

## Open / Future

- Android implementation (seam ready, branch stubbed).
- Pinned-release `--update` with integrity verification.
- Optional Homebrew tap as alternative install path.
```
