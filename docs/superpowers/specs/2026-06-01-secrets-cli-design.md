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
file. The tool is **stack-agnostic** — there is no platform concept. A config lists,
per 1Password vault, the local files that belong to it; `read`/`write` sync those
files. This works identically for iOS, Android, or any project that keeps secret
files in the repo.

> **Design evolution note.** The original design had a `platform` field + iOS/Android
> hooks and an `environments`/`files`/`fileVaults` config. Review feedback (and
> comparing the iOS and Android consumers, which differ only in data) collapsed this
> to the generic vault→files model below. Sections updated accordingly.

## Goals

- One installable command with app-deploy-style subcommand structure.
- Generic, shared read/write logic — no platform/stack-specific code.
- Zero per-project script copying — projects carry only config.
- Support both interactive (`op signin`) and CI (`OP_SERVICE_ACCOUNT_TOKEN`) auth.

## Non-Goals

- Glob/folder patterns in config (concrete file paths only — see Open/Future).
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
│   ├── __read.sh               # __read — download files (from ios/read.sh)
│   ├── __write.sh              # __write — upload files (from ios/write.sh)
│   ├── __doctor.sh             # __doctor — diagnostics
│   ├── __auto_update.sh        # __script_auto_update — --update
│   └── helpers/
│       ├── __op_utils.sh       # op/jq checks, session/service-account, vault access
│       ├── __config.sh         # load + parse JSON config → bash vars/arrays
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
1. `tmp="$(mktemp -d)"` + `trap 'rm -rf "$tmp"' EXIT` (unique temp, no CWD litter)
2. `git clone --quiet <repo> "$tmp"`
3. Announce `Replacing existing install…` if the bin/sources already exist
4. `cp "$tmp/infinum-secrets.sh" <bindir>/infinum-secrets`
5. `cp -a "$tmp/sources/." <bindir>/.infinum-secrets-sources/`
6. `chmod +rx` on entry + sources
7. Prompt `Do you want to proceed? [y/n]` unless `--silent`.

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
  "vaults": [
    { "name": "staging",    "vault": "project-projectname-android-staging",
      "files": ["secrets-staging.properties"] },
    { "name": "production", "vault": "project-projectname-android",
      "files": ["secrets.properties"] }
  ]
}
```

The schema is vault-centric: each vault owns the local files that belong to it.
There is no `platform` and no shared `path` root — each file path is written out in
full so files can live anywhere (flexible for layouts where a file sits outside the
usual secrets folder).

### Field reference

| Field | Type | Meaning |
|-------|------|---------|
| `vaults` | object[] | The 1Password vaults, each owning a set of files. |
| `vaults[].vault` | string | The 1Password vault name (required). |
| `vaults[].name` | string | Optional friendly label; `read <label>` / `write <label>` resolve it. |
| `vaults[].files` | string[] | File paths relative to the repo/CWD that live in this vault (required, non-empty). |

**Document title:** the 1Password document title is the file's **name (with
extension)** — e.g. `secrets-staging.properties`, or `Keys/Keys.staging.swift` →
`Keys.staging.swift`. The folder is never part of the title; it comes from the
configured file path. This matches the Android consumer's existing vaults exactly.

### Parsing (`helpers/__config.sh`)

`__config.sh` locates `secrets.config.json` (cwd), validates it is valid JSON with
the required `vaults` key and that each vault has a non-empty `vault` + `files`,
then flattens it into bash variables:

- `vaults` → bash array of vault **names** (`.vaults[].vault`)
- `file_vaults` → bash array of `"relpath:vault"` (one per file, order preserved) —
  iterated by both `read` and `write`
- `vault_aliases` → bash array of `"alias:vault"` (label→vault and vault→vault) for
  resolving the optional filter arg

Missing config → error pointing user to `infinum-secrets init`.

## Shared Logic (no platform)

`__read` and `__write` are fully generic and iterate `file_vaults`. There is no
platform branch or hook — iOS, Android, and any other stack are just different data
in the same config.

## Commands

### `init`
Writes a generic `secrets.config.json` template (inline heredoc — no external template
file). Refuses to overwrite an existing config (requires `--force`). Needs neither
`op` nor `jq` (it only writes a static file). After writing, it opens the file in the
user's editor (best-effort): `$INFINUM_SECRETS_OPENER`, then `$VISUAL` / `$EDITOR`,
then `open` / `xdg-open`. Opening is skipped when non-interactive or with `--no-open`,
and never fails the command.

### `read [vault]`
For each configured file, fetches the document titled `<filename>` from its vault and
writes it to the file's path, creating folders as needed. Skips files whose vault the
user can't access. Optional `vault` arg (name or friendly label) restricts to one
vault. Config loaded from JSON.

### `write [vault]`
For each configured file that exists locally, uploads it to its vault with title
`<filename>` (create if absent, edit if present). Missing local files are skipped.
Checks write access, previews, and confirms before upload — the confirmation is
skipped when non-interactive (CI). Optional `vault` arg restricts to one vault.
Config loaded from JSON.

### `doctor` (alias `status`)
Diagnostics:
- `op` installed? `jq` installed?
- Signed in? — probed with a **bounded** `op whoami` (`op_signed_in`) that hard-kills
  `op` after ~8s so a locked/unresponsive 1Password app can't hang doctor. `op whoami`
  works for both personal sign-ins and service-account tokens; doctor reports which.
- `secrets.config.json` present, valid JSON, required keys present?
- Per-vault read + write access table (reuses `print_vault_access`). Under a service
  account, write access is assumed (no user identity to introspect; `op` enforces on
  write).
Exits non-zero if a hard prerequisite is missing.

### `--version`
Prints `infinum-secrets $VERSION` from `__constants.sh`.

### `--update`
Re-runs the installer flow (clone + overwrite entry + sources). Pulls `main`.
_Future improvement:_ pin to a release tag + integrity check before overwriting a
secrets-handling tool.

### `--help` / `-h`
Single heredoc: usage, description, commands, examples.

## Authentication

- **Interactive:** `read`/`write` don't pre-check the session — `op` prompts for
  sign-in on its first call via the 1Password desktop-app integration (the same way
  `op document get` does on its own). No custom sign-in flow.
- **CI / non-interactive:** `OP_SERVICE_ACCOUNT_TOKEN` — `op` uses it automatically
  (no config). Service accounts have no user identity, so `can_write_vault` skips the
  user-permission check for them (read-only unless granted write; `op` enforces on the
  actual write).
- **`doctor` only** probes the session with a **bounded** `op whoami` (`op_bounded`,
  hard SIGKILL after ~8s) — a diagnostic must report status without hanging, and `op`
  can block indefinitely on the app integration while ignoring soft signals. `read`/
  `write` deliberately do not bound `op` so its interactive prompt works normally.

## Error Handling

- `set -euo pipefail` in the entry; empty-array expansions guarded (`"${arr[@]+…}"`)
  and arrays initialized (`local -a x=()`) for bash 3.2.
- Missing `op`/`jq` → clear install instructions, non-zero exit (in `__op_utils.sh`
  + surfaced by `doctor`).
- Missing/invalid config → message + `infinum-secrets init` hint.
- No vault access → graceful per-file skip with `[!]` notice.
- Not signed in → `op`'s own first call prompts (interactive) or errors (CI without a
  token); `read`/`write` don't intercept this. Only `doctor` bounds the probe.

## Versioning

`VERSION` constant in `__constants.sh`, surfaced via `--version`. `--update` re-clones
latest `main`. Workflow/config-format changes (if any) versioned separately later if
needed.

## Migration of Existing Scripts

| Today | Becomes |
|-------|---------|
| `ios/.onepassword/config.sh` | `secrets.config.json` + `helpers/__config.sh` parser |
| `ios/.onepassword/utils.sh` | `sources/helpers/__op_utils.sh` |
| `ios/.onepassword/read.sh` | `sources/__read.sh` (`__read` function) |
| `ios/.onepassword/write.sh` | `sources/__write.sh` (`__write` function) |

Logic reshaped from standalone `main "$@"` scripts into sourced `__<command>`
functions, config from JSON. Existing vaults keep working: the document title is the
file name, matching how the Android consumer already stores documents.

## Testing

- Pure helpers (config parsing, `resolve_vault_filter`, `doc_title_for`, `op_bounded`)
  are covered by [bats](https://github.com/bats-core/bats-core).
- `read`/`write`/`doctor` are exercised end-to-end against a **fake `op` shim** on
  `PATH` (records args, returns canned output) — verifies title/vault/path handling
  with no real 1Password account.
- `op_bounded` has a test proving it hard-kills a hung command; `doctor` has a test
  proving it doesn't hang when `op` is unresponsive.
- Lint with `shellcheck` (clean).

## Open / Future

- **Glob / folder patterns.** Config takes concrete file paths only. Globs can't be
  supported for `read` without a different placement model (a glob is a set, not a
  document title/destination; and the filename-only title can't reconstruct arbitrary
  paths). Neither current consumer needs it. If required, add an explicit "folder"
  entry type (`read` lists the vault) rather than overloading globs.
- **Homebrew formula** declaring `op` + `jq` as dependencies (replaces the curl
  installer and the runtime presence checks).
- Pinned-release `--update` with integrity verification.
```
