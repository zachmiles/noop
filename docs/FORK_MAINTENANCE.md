# Fork Maintenance

This repository is Zach's personal fork of NOOP. The goal is to keep local
customizations clear while still making it routine to bring in upstream changes
from `NoopApp/noop`.

## Remotes

- `origin`: Zach's fork, `https://github.com/zachmiles/noop.git`
- `upstream`: canonical project, `https://github.com/NoopApp/noop.git`

If `upstream` is missing locally, add it once:

```bash
git remote add upstream https://github.com/NoopApp/noop.git
git remote set-url --push upstream DISABLED
git fetch upstream --prune
```

The disabled push URL is intentional: this fork should fetch and merge from
upstream, but pushes should go to `origin`.

## Local Sources Of Truth

- [`docs/FORK_CHANGES.md`](FORK_CHANGES.md): running log of Zach-specific changes,
  why they exist, and what to watch during upstream syncs.
- `git log upstream/main..HEAD`: committed fork-only changes.
- `git status --short --branch`: uncommitted local work that must not be lost.

## Upstream Sync Workflow

Use this checklist when Zach asks to check for upstream updates or pull them in.

1. Inspect local state first:

   ```bash
   git status --short --branch
   git remote -v
   git branch -vv
   ```

2. Ensure the upstream remote exists and fetch both remotes:

   ```bash
   git remote get-url upstream || git remote add upstream https://github.com/NoopApp/noop.git
   git remote set-url --push upstream DISABLED
   git fetch origin --prune
   git fetch upstream --prune
   ```

3. Summarize what changed before merging:

   ```bash
   git log --oneline --decorate HEAD..upstream/main
   git diff --stat HEAD..upstream/main
   git log --oneline --decorate upstream/main..HEAD
   ```

4. Compare upstream changes against the local-change log. Pay special attention
   to any files listed under "Watch during upstream syncs" in
   [`docs/FORK_CHANGES.md`](FORK_CHANGES.md).

5. Create a sync branch from the current fork state:

   ```bash
   git switch -c sync/upstream-YYYY-MM-DD
   git merge --no-ff upstream/main
   ```

6. If conflicts occur, resolve them deliberately and add an entry to
   [`docs/FORK_CHANGES.md`](FORK_CHANGES.md) describing the decision.

7. Run the relevant validation for the files touched. For Apple app build, run,
   test, and debug tasks, use FlowDeck first. For package-only changes, run the
   narrow Swift package tests when they do not require an Apple runtime.

8. Update [`docs/FORK_CHANGES.md`](FORK_CHANGES.md) with:

   - upstream range merged
   - conflict decisions
   - local customizations preserved or changed
   - validation performed
   - anything to revisit later

9. Merge the sync branch back or commit the merge on `main` only after the log is
   updated and the user has reviewed any unresolved overlap.

## Conflict Policy

- Prefer preserving local fork behavior when the upstream change is unrelated.
- Prefer upstream behavior when the local change was only temporary or replaced
  by a better upstream implementation.
- When both are plausible, keep the code buildable and record the unresolved
  product decision in [`docs/FORK_CHANGES.md`](FORK_CHANGES.md).
- Never discard uncommitted work just to make an upstream merge easier.
