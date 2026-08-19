# Setting up a project with 1Password secrets

Passwords, API keys, secure tokens, and confidential data are secrets — they
don't belong in the repository. We store them in [1Password](https://1password.com)
and sync them with local files using [`app-secrets`](../README.md), which
wraps the [1Password CLI (`op`)](https://developer.1password.com/docs/cli/).

This guide covers setting up a **new project**. For moving an existing project
off the legacy HashiCorp Vault workflow, see
[Migrating from Vault](migrate-from-vault.md).

## 1. Request the project vaults

Each project typically gets two 1Password vaults, one per environment tier:

- `project-<project-name>-ios` — production / App Store builds
- `project-<project-name>-ios-staging` — staging / dev builds

The project lead or a senior engineer requests them via the `#devops-hotline`
Slack channel, with **Manage** access rights (read + write + ability to add
members), so they can add the rest of the team without going through DevOps
for every change.

Projects with more environments can either request one vault per environment
or keep everything non-production in the `-staging` vault — the tool stores
each file's relative path on its 1Password item, so same-named files from
different environment folders coexist in one vault.

## 2. Team member prerequisites

Every team member needs:

- a company 1Password account,
- the 1Password desktop app, signed in, with CLI integration enabled
  (**Settings → Developer → Integrate with 1Password CLI**),
- membership in the project vaults (added by the lead from step 1).

## 3. Install the tooling

```bash
brew install infinum/tap/app-secrets   # pulls in jq
brew install --cask 1password-cli      # op is cask-only, so it installs separately
```

Update the CLI later with `brew upgrade app-secrets`.

## 4. Lay out the secret files

Keep secret files in a gitignored directory, split **per environment** — one
file per environment, no shared files:

```
MyApp/SupportingFiles/Vault/
 ├─ Keys/
 │    Keys.production.swift
 │    Keys.staging.swift
 ├─ GoogleService/
 │    GoogleService-Info.production.plist
 │    GoogleService-Info.staging.plist
```

> [!IMPORTANT]
> **No `.shared` files.** The old single `Keys.shared.swift` with
> `#if DEVELOPMENT / #elseif STAGING` branching doesn't fit a two-vault split.
> Use one file per environment and let the Xcode target pick the right file
> per build configuration.

Add the `.gitignore` rule (e.g. `MyApp/SupportingFiles/Vault/*`) **before**
putting any secrets there. The directory name `Vault/` is a convention kept
from the old workflow; the storage backend is 1Password.

## 5. Create the config

In the project root:

```bash
app-secrets init      # scaffolds .secrets.config.json and opens it
```

Optionally run `app-secrets doctor` to confirm the tooling, your sign-in,
and per-vault access before going further. It only reports; it changes nothing.

`.secrets.config.json` is vault-centric — each vault owns the files that
belong to it. Entries can be literal paths or glob/folder patterns; with a
per-environment folder layout, folder shorthand keeps the config maintenance-free:

```json
{
  "vaults": [
    {
      "name": "staging",
      "vault": "project-myapp-ios-staging",
      "files": ["MyApp/SupportingFiles/Vault/**/*.staging.*"]
    },
    {
      "name": "production",
      "vault": "project-myapp-ios",
      "files": ["MyApp/SupportingFiles/Vault/**/*.production.*"]
    }
  ]
}
```

See the [README's Configuration section](../README.md#configuration) for the
full schema, the pattern dialect, typical setups, and how the stored `path`
field keeps same-named files apart.

## 6. Daily usage

```bash
app-secrets read              # download every configured file to its path
app-secrets write             # upload every configured local file
app-secrets read staging      # scope either command to one vault
```

`write` previews the upload and asks for confirmation when run interactively.
Vaults you can't access are skipped rather than failing the run.

## 7. CI (Bitrise)

CI authenticates with a 1Password **service account token** — no desktop app,
no prompts.

1. The same person who requested the vaults asks DevOps in `#devops-hotline`
   for a service account with read access to the project vaults. One owner —
   don't have several people requesting accounts for the same project.
2. In Bitrise, add a Secret Environment Variable `OP_SERVICE_ACCOUNT_TOKEN`
   with the token (marked secret so it never prints in logs).
3. Add two script steps right after `git clone`:

   **Step A — install tooling**. Re-running is safe: `brew install` on an
   already-installed package warns and moves on.

   ```bash
   #!/usr/bin/env bash
   set -e
   brew install infinum/tap/app-secrets
   brew install --cask 1password-cli
   ```

   **Step B — fetch secrets**:

   ```bash
   #!/usr/bin/env bash
   set -e
   # OP_SERVICE_ACCOUNT_TOKEN authenticates op non-interactively
   app-secrets read
   ```

> [!WARNING]
> **One secrets source on CI.** There is no dual Vault / 1Password support:
> the migration replaces the Vault CI steps outright. If an older release
> branch needs CI builds after the switch, cherry-pick the migration commits
> onto it so it has 1Password support — don't resurrect the Vault steps.
