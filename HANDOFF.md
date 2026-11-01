<!-- Relay handoff note. Lives only on relay branches; deleted before review. -->
# Handoff

- roadmap_item: `reactor` follow-up (owner decisions of 2026-10-27, OQ-23, OQ-26): `reactor.shield(fn)` with its own deadline; an `on_unobserved_failure` hook; `core.IoError` as a base class that `reactor.IoError` extends.
- status: in-progress
- lock_until: 2026-11-01T11:22:54Z
- last_update: 2026-11-01T09:52:54Z

## Done

- Step 1: `core.IoError` added; `reactor.IoError` extends it (tests, README, object-model.md, concurrency.md, CHANGELOG). core and reactor tests ok.
- Step 2: `on_unobserved_failure(err, future)` Reactor option (called when a detached computation fails with no active watcher on its future; hook errors discarded; not for cancelled). Tests `unobserved_failure_test.lua`, concurrency.md rule 2, README, CHANGELOG. Website has no page on detach: nothing to update.

## Next steps

1. `reactor.shield(fn, opts)` with its own deadline (spec in concurrency.md, tests: cleanup can suspend while cancelled, deadline bounds a stuck peer, nesting, virtual clock).
2. Then `BufferedWriter:close` flush under cancellation belongs to the `net` follow-up or this item per OQ-29: check networking.md.
3. Finish: tick the roadmap item, restore the gate's HANDOFF.md (see below), mark ready.

## Decisions taken (and where they are recorded)

- Stacked branch: this branch is based on `claude/relay-phase-1-gate` (PR #47) because the owner decisions and specs live only there; the pull request targets that branch. Its `HANDOFF.md` is overwritten here: at the end restore it with `git checkout origin/claude/relay-phase-1-gate -- HANDOFF.md` instead of deleting it.

## Doubts and questions for the owner

- None yet.

## Commands to re-run

```sh
eval "$(luarocks path)"
lua tools/run.lua test core
lua tools/run.lua test reactor
lua tools/run.lua lint
lua tools/run.lua check-annotations
```
