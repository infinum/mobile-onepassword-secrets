# Migrating from Vault to 1Password

The legacy [HashiCorp Vault](https://www.vaultproject.io) workflow (a `.vault/`
folder with `read.sh`/`write.sh` calling `vault.infinum.co`) is deprecated in
favor of 1Password + [`app-secrets`](../README.md). New projects should
follow [Project setup](project-setup.md) from day one; this guide moves an
existing project over.

**The migration is owned by one person** — the project lead or a senior
engineer. They request the vaults, get **Manage** access, add the team, and
request the CI service account. Don't have multiple people pinging DevOps for
the same project.

## Checklist

1. **Request the 1Password vaults** via `#devops-hotline` (see
   [Project setup](project-setup.md#1-request-the-project-vaults) for naming
   and access conventions), then add the rest of the team.

2. **Pull the latest secrets one last time** with the legacy script:
   `bash ./.vault/read.sh` (needs a working `VAULT_AUTH_TOKEN`). The local
   files become the source of truth for the upload.

3. **Split any `*.shared.*` files.** A `Keys.shared.swift` with
   `#if DEVELOPMENT / #elseif STAGING` branching doesn't fit the per-vault
   split — break it into per-environment files (`Keys.staging.swift`,
   `Keys.production.swift`) and update Xcode target membership / Build
   Settings.

4. **Install the CLI and create the config**: `app-secrets init` in the
   project root, then map each environment's files to its vault in
   `.secrets.config.json`. With per-environment folders, folder shorthand
   (`Configurations/Staging/`) or suffix patterns (`Vault/**/*.staging.*`)
   keep the config short — see the
   [README's typical setups](../README.md#typical-setups).
   Validate with `app-secrets doctor`: it must show a signed-in session
   and ✓ read/write access on every configured vault before you continue.

5. **Upload with `app-secrets write`.** Review the preview line by line —
   every expected file, each targeting the right vault, nothing extra.

6. **Verify the round-trip**: move the local secret files aside, run
   `app-secrets read`, and compare the restored files against the copies
   (`diff -rq`). Contents must be identical.

7. **Switch CI to 1Password.** Replace the Vault read step with the two
   script steps from [Project setup](project-setup.md#7-ci-bitrise) and add
   the `OP_SERVICE_ACCOUNT_TOKEN` secret.

   > [!WARNING]
   > **No dual Vault / 1Password support on CI.** The 1Password steps replace
   > the Vault steps outright — don't add branch-detection logic that keeps
   > both alive. If an older release branch needs CI builds after the switch,
   > **cherry-pick the migration commits onto that branch** so it has
   > 1Password support.

8. **Delete the `.vault/` folder** and remove remaining references to it,
   `VAULT_AUTH_TOKEN`, or `VAULT_ADDR` from CI configs, fastlane, and the
   project README. The gitignored local `Vault/` directory (the one holding
   the actual secret files) keeps its name and `.gitignore` rule.

## Agent-assisted migration

Steps 2–8 are mechanical enough to delegate. Expand the block below, copy it
whole, and paste it into an agent (e.g. Claude Code) opened at the project you
want to migrate — it discovers the legacy scripts, generates the config, and
walks the upload and verification with you.

<details>
<summary><b>Migration prompt</b> — click to expand, then copy the whole block</summary>

````markdown
Migrate this project's secret-file syncing from the legacy HashiCorp Vault
scripts to [`app-secrets`](https://github.com/infinum/mobile-onepassword-secrets),
which syncs the same files with 1Password vaults via a `.secrets.config.json`.

**The legacy workflow you are replacing** usually looks like this: a `.vault/`
(or `vault/`, `scripts/vault/`) folder with a `read.sh` and `write.sh` that call
the `vault` CLI against `https://vault.infinum.co:8200/`, authenticate with a
GitHub token in `VAULT_AUTH_TOKEN`, and read secrets from a path like
`<platform>/<project-name>/<Environment>`, where each **field** of the secret is
a **file name** and its value is the file's contents. `read.sh` typically holds
the configuration as shell variables: a local root `path`, an `environments`
array, and one `generate_file "<file>"` call per secret file, writing each to
`<path>/<Environment>/<file>`.

## Ground rules — read first

- **Never print, log, or quote the contents of any secret file.** Refer to
  files by path only. Do not cat/head/grep them; byte-compare with `diff -q`.
- **Never commit secret files or tokens.** Before finishing, verify the secret
  paths are covered by `.gitignore`.
- **The old Vault stays untouched.** This migration only reads from it (via the
  existing scripts, if at all). Never `vault write`, and never delete old data.
- **Ask before every irreversible or outward action**: uploading to 1Password,
  deleting the old scripts, changing CI.
- If anything you discover contradicts these instructions (unexpected script
  shape, extra local files, missing environments), surface it and ask instead
  of guessing.

## Step 1 — Discover the old setup

Locate the legacy scripts: look for `.vault/`, or grep the repo for
`vault read`, `VAULT_ADDR`, or `vault.infinum.co`. From `read.sh` extract:

- the local root path (`path=...`),
- the environment list (`environments=(...)`),
- the secret file names (the `generate_file "<name>"` calls, or
  `vault read -field=<name>` usages),
- the project name and secret path template (`<platform>/<project>/<env>`).

Cross-check `write.sh` for the same values and note any discrepancy.

Then inventory what actually exists on disk under `<path>/<Environment>/`.
The script constants say what *should* exist; the local tree says what a
`write` would actually upload. Report both lists and flag differences
(extra files, missing environments, stray files that look non-secret).

## Step 2 — Decide where the config lives and re-root the paths

`.secrets.config.json` belongs where the team will run `app-secrets`
(usually the repo root; in a monorepo it can be a subproject folder). The
legacy scripts' `path` is often relative to the repo root and may include a
subproject prefix — recompute every file path **relative to the config's
directory** and use those in the config.

## Step 3 — Map environments to 1Password vaults

1Password vaults must already exist (admins create them; the tool never does).
Run `op vault list` and try to match the project against Infinum's naming
convention (`project-<name>` for production, `project-<name>-<suffix>` for
other environments). Then propose a mapping and **confirm it with the runner**
before going further. Two shapes work:

- **One vault per environment** — e.g. `project-x-development`,
  `project-x-test`, `project-x-staging`, and `project-x` for production.
- **Consolidated** — e.g. everything non-production in `project-x-staging`,
  production in `project-x`. Same-named files from different environment
  folders are fine in one vault: the tool stores each file's relative path on
  the 1Password item and keeps them apart.

If some vaults don't exist yet, stop and list exactly which ones need to be
created and by whom, then continue once they exist.

## Step 4 — Generate the config

Run `app-secrets init --no-open` in the chosen directory (or create the
file by hand following the README) and fill in one entry per vault. Prefer
**folder shorthand** per environment when the installed tool supports patterns
(see the README's *Glob / folder patterns* section) — new secret files then
sync without config edits:

```json
{
  "vaults": [
    { "name": "development", "vault": "project-x-development",
      "files": ["Path/To/Configurations/Development/"] },
    { "name": "production", "vault": "project-x",
      "files": ["Path/To/Configurations/Production/"] }
  ]
}
```

If the installed version predates pattern support, list every file explicitly
with its full relative path instead.

Validate with `app-secrets doctor`: it checks tooling, sign-in, and prints
the per-vault read/write access matrix. Resolve ✗ rows (access, naming) with
the runner before continuing.

## Step 5 — Seed 1Password

Make sure the local files are current: if the runner has a working
`VAULT_AUTH_TOKEN`, run the legacy `read.sh` one last time; otherwise have the
runner confirm the local files are the latest.

Then run `app-secrets write`. **Review the preview line by line with the
runner before confirming**: every expected file present, each targeting the
agreed vault, nothing extra.

## Step 6 — Verify the round-trip

1. Copy the secret files aside to a temp directory (outside the repo).
2. Delete the local secret files.
3. Run `app-secrets read`.
4. `diff -q` (or `diff -rq` on the folders) each restored file against its
   copy. Contents must be identical; report the result. If anything differs
   or is missing, restore from the copies and investigate before retrying.

## Step 7 — Clean up (only after the runner approves)

- Delete the legacy vault scripts.
- Grep CI configs, fastlane, Makefiles, and READMEs for references to them,
  `VAULT_AUTH_TOKEN`, or `VAULT_ADDR`; replace the Vault CI read step with
  the 1Password steps (`OP_SERVICE_ACCOUNT_TOKEN` — see the tool README's
  Authentication section and docs/project-setup.md). Do **not** add dual
  Vault/1Password branch-detection to CI: older branches that need builds
  cherry-pick the migration commits instead.
- Verify `.gitignore` still covers all secret paths.
- Add a short note to the project README: how to install `app-secrets`
  and that `read`/`write` replace the old scripts.

## Final report

Summarize for the runner: the environment→vault mapping, how many files per
vault, the doctor access matrix, the round-trip verification result, and
which cleanup items are done vs. pending.
````

</details>
