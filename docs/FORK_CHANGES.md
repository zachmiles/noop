# Fork Changes

This is the running log for Zach-specific changes in this fork. Keep it updated
whenever local behavior diverges from `NoopApp/noop` or an upstream sync requires
a decision.

## How To Add Entries

Add newest entries first. Each entry should include:

- date
- commit or working-tree status
- files touched
- reason for the local change
- upstream sync watchpoints
- validation performed

Template:

```md
## YYYY-MM-DD - Short title

- Status:
- Files:
- Reason:
- Watch during upstream syncs:
- Validation:
- Notes:
```

## 2026-06-24 - Fork maintenance workflow

- Status: pending commit in this fork.
- Files:
  - `AGENTS.md`
  - `docs/FORK_MAINTENANCE.md`
  - `docs/FORK_CHANGES.md`
  - `README.md`
- Reason: establish a repeatable process for checking and merging upstream NOOP
  changes while preserving Zach-specific customizations.
- Watch during upstream syncs: documentation-only unless upstream later adds its
  own fork-maintenance guidance or `AGENTS.md`.
- Validation: documentation review only.
- Notes: future upstream syncs should update this log before the sync is treated
  as complete.

## 2026-06-24 - Local bundle identifier and team configuration

- Status: committed locally as `fd8dcac Update bundle identifiers and team in project config`.
- Files:
  - `project.yml`
- Reason: local fork configuration for Zach's build/signing identity.
- Watch during upstream syncs: upstream edits to `project.yml`, especially bundle
  identifiers, signing/team settings, entitlements, target settings, or product
  names.
- Validation: not rerun as part of this documentation pass.
- Notes: preserve this local configuration unless Zach explicitly asks to revert
  to upstream identifiers/signing.

## 2026-06-24 - Localization updates

- Status: committed locally as `75aef62 Add/update translations in Localizable.xcstrings`.
- Files:
  - `Strand/Resources/Localizable.xcstrings`
- Reason: local localization fix/update.
- Watch during upstream syncs: upstream localization changes may overlap with
  this file; review merge conflicts carefully instead of accepting either side
  wholesale.
- Validation: not rerun as part of this documentation pass.
- Notes: preserve this local localization work unless Zach explicitly replaces it
  with upstream strings.
