# Versions and compatibility

MakeItLean is versioned so that an app keeps working when the framework moves on, and so that a
change to what an audit requires is never silent.

## Where versions live
- **The framework:** `VERSION` at the repository root (for example `0.6.0`). `mil --version` prints it
  with the commit.
- **An app:** `framework_version` in its `mil.json`, written by `mil init`. `mil.json` is locked at the
  freeze, so the signed-off spec names the framework version it was approved under. An app outside
  the checkout also pins the framework's exact commit in its `lakefile.lean`; `mil` checks that the
  pinned framework's `VERSION` agrees with `framework_version`.

## What `mil` accepts
Every `mil judge`, `mil check` and `mil audit` compares the app's `framework_version` with its own:

| The app is for… | `mil` does |
|---|---|
| this version, or an older one it still supports | runs |
| a newer framework than this `mil` | refuses: update your framework checkout |
| a version older than the oldest it supports | refuses: run `mil upgrade` |
| no version (created before versioning) | runs with the rules that applied then, and warns |

## The policy
- **Before 1.0, a minor release (0.x.0) may change what an audit requires;** a patch release
  (0.x.y) never does. Every release note lists its audit-contract changes.
- **A fix that closes a way to cheat applies to every app, whatever its version.** An old app that
  relied on the hole fails its audit until it is upgraded. A guarantee that can be bypassed is not
  kept for compatibility.
- **A new requirement on an app's content** (for example, a required spec critic, or rules on
  `TRUST.md`) applies to apps whose `framework_version` is at least the version that introduced it,
  or that were upgraded to it.

## Upgrading an app
```bash
mil upgrade <app>/mil.json            # dry run: prints every change, and what the roles must do
mil upgrade --apply <app>/mil.json
```
`mil upgrade` sets `framework_version`; adds the `mil.json` sections newer versions need (derived
from the app's conventions, printed for review); moves an external app's pinned framework commit;
and keeps an existing `spec.lock` as `spec.lock.v<N>`. It never edits spec, implementation, critic or
trust files: it lists what they need. **Locked files change, so an upgraded app needs a new review
and sign-off** (`mil review`, the user's approval, `mil freeze`), as for any spec change.

## Release notes

### 0.6.0 (Phase 6)
The first versioned release. Audit-contract changes, all of which apply to apps that declare 0.6.0:
- `mil` generates the verified-code audit from `mil.json`'s `audit` section; an app's own
  `impl/audit.lean` is no longer read (legacy apps: only if its hash is in `lean/legacy_audits.json`).
- The spec's `lake-manifest.json` is in the lock; the implementation must build against exactly the
  spec's dependencies (applies to every app: it closes a bypass).
- `mil selftest` is part of the audit for apps with a shell; `mil.json` may set its `selftest`
  section.
- A spec critic (`<App>/SpecCritic/`, at least one `#guard`) is required (every app).
- `TRUST.md` rules: Proven rows cite an anchored name; "Tested against the model" rows cite
  `selftest`; every surviving mutant is explained.
- New: `mil init --lib`, `mil check`, `mil doctor`, `mil upgrade`, `mil --version`.

## Making a release (maintainers)
1. Update `VERSION` and this file's release notes (every audit-contract change).
2. If old apps no longer meet the contract, raise `minSupported` in `cli/Mil/Main.lean`.
3. `tests/all.sh` green.
4. Commit, tag `v<version>`, push the tag.
