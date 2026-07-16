# Android Support — Implementation TODO

The CLI ships with the **platform seam in place but Android stubbed**. `platform_validate android`
returns an error ("not yet implemented"), so `read`/`write` refuse to run for an Android config,
while `init --platform android` still scaffolds a config. This doc lists what's needed to make
Android a first-class platform.

## Current state (what already exists)

- [`sources/helpers/__platform.sh`](../sources/helpers/__platform.sh)
  - `platform_default_path android` → `app/src/main/secrets` (placeholder default)
  - `platform_validate android` → **errors, exit 1** (the stub gate)
- `init --platform android` writes a config with `platform: "android"` and the default path.
- All shared logic (`__read`, `__write`, `__config`, `__op_utils`) is platform-agnostic today and
  keys off the JSON config only.

## Open questions to resolve first (design)

Answer these before writing code — they determine whether the shared logic suffices or needs
Android-specific hooks.

- [ ] **File/dir layout.** Files are routed by matching their path **relative to `path`** against a
      vault's glob `patterns`; the relative path becomes the 1Password document title. What is the
      real Android convention?
  - Per-flavor source sets: `app/src/<flavor>/` (e.g. `app/src/staging/google-services.json`) —
    expressible as patterns like `*/staging/*`, `*/production/*`.
  - A single secrets dir with env-suffixed names (mirrors iOS) — `*.staging.*`, `*.production.*`.
  - Gradle-consumed `secrets.properties` / `keystore.properties` at module root.
- [ ] **Pattern expressiveness.** Confirm the chosen layout is expressible with the current relative-
      path globs (`get_vault_for_file` / `vault_matches_file`). Per-flavor dirs and env-suffixed names
      both are, so Android likely needs **no** new matching code — just the right `patterns` in the
      config. Verify before assuming.
- [ ] **Which files.** Typical Android secrets: `google-services.json`, `*.keystore` / `*.jks`,
      `keystore.properties`, `secrets.properties`, `local.properties` fragments. Confirm the set.
- [ ] **Vault naming.** Confirm convention, e.g. `project-<name>-android`,
      `project-<name>-android-staging` (parallel to iOS).
- [ ] **1Password item type.** iOS uses `op document`. Do any Android secrets belong as
      structured items/fields instead of documents? (Likely still documents — confirm.)

## Implementation checklist

Once the layout is decided:

- [ ] **`platform_validate`**: change the `android` branch in
      [`sources/helpers/__platform.sh`](../sources/helpers/__platform.sh) to `return 0`.
- [ ] **`platform_default_path`**: replace the placeholder `app/src/main/secrets` with the agreed
      real default.
- [ ] **Platform hooks (only if Android genuinely diverges):** the config is now vault + patterns,
      and read/write route purely on the relative-path glob match — which is platform-agnostic. Add a
      hook only if Android needs something the pattern model can't express, e.g.:
  - `platform_local_root` → a different local base than a flat `path` (e.g. per-module roots)
  - `platform_document_title <relpath>` → a title scheme other than the relative path
  Keep iOS behavior identical; branch on `$platform` inside the hook, not scattered through the
  command bodies. (Preserves the "shared logic, platform config" design.)
- [ ] **Config template / `init`:** if Android wants different default vaults/patterns, have `init`
      emit an Android-specific template (e.g. `sources/secrets.config.android.json`) selected by
      `--platform`, instead of only patching `platform`/`path`.
- [ ] **`__config.sh`:** only touch if the Android schema needs a genuinely new field. The current
      `platform` + `path` + `vaults[{name,patterns}]` schema should cover per-flavor layouts as-is.

## Tests (bats)

- [ ] `tests/fixtures/valid.android.config.json` — a representative Android config.
- [ ] `tests/platform.bats` — update: `platform_validate android` now returns 0; assert the real
      default path.
- [ ] `tests/config.bats` — parse the Android fixture (any new fields).
- [ ] `tests/op_flow.bats` — add Android read/write cases using the `op` shim, mirroring the iOS
      cases, asserting the correct local paths and `op` document args for the Android layout.
- [ ] Keep every existing iOS test green (no regressions to the shared logic).

## Docs

- [ ] Update [`README.md`](../README.md): drop the "Android is scaffolded" caveat; document the
      Android config shape + file layout.
- [ ] Update the design spec
      [`docs/superpowers/specs/2026-06-01-secrets-cli-design.md`](superpowers/specs/2026-06-01-secrets-cli-design.md):
      move Android from "Non-Goals / scaffolded" to implemented; record the layout decision.
- [ ] Update `doctor` if Android needs extra checks (e.g. presence of expected flavor dirs).

## Guardrails

- Do not fork `__read`/`__write` into `__read_android`/`__read_ios`. The chosen design is **shared
  logic + platform config/hooks** — divergence lives behind small hook functions, not duplicated
  command bodies.
- Maintain bash 3.2 compatibility (no `mapfile`, no `${var,,}`, guard empty-array expansions with
  `"${arr[@]+"${arr[@]}"}"`).
- Keep `shellcheck` clean and every command's `-h` working without `op`/config.
