# AGENTS

This is Zach's personal fork of NOOP. Preserve upstream compatibility while keeping
local customizations easy to audit.

## Fork Maintenance

- Canonical upstream is `https://github.com/NoopApp/noop.git`.
- This fork's `origin` is Zach's fork.
- Before pulling upstream changes, read [`docs/FORK_MAINTENANCE.md`](docs/FORK_MAINTENANCE.md)
  and update [`docs/FORK_CHANGES.md`](docs/FORK_CHANGES.md).
- Treat local customizations as intentional unless the user explicitly says to
  discard them.
- When upstream changes overlap local files, stop and document the conflict or
  decision in the fork change log instead of silently choosing one side.

## Tooling

- Always use parallel tool calls when independent reads, searches, or inspections
  can run at the same time.
- For Apple-platform build, run, test, and debug work, use the FlowDeck skill and
  CLI first. Do not use `xcodebuild`, `xcrun simctl`, or other Apple CLI tools
  unless FlowDeck is unavailable or the user explicitly asks for a fallback.
- Prefer an iPhone Air simulator when using an iPhone simulator.
- This repo may have uncommitted user work. Check `git status --short --branch`
  before editing, merging, staging, or committing.
