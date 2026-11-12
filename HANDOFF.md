<!-- Relay handoff note. Lives only on relay branches; deleted before review. -->
# Handoff

- roadmap_item: `reactor` follow-up: specify then implement `offload` (Lua functions on the libuv thread pool), split from the Phase 1 item (OQ-27).
- status: in-progress
- lock_until: 2026-11-12T08:35:48Z
- last_update: 2026-11-12T07:05:48Z

## Done

- Claimed the item; draft pull request #176.
- Specification: `docs/architecture/concurrency.md` section "Offload"; OQ-119 with mirror issue #177.
- Implementation: `reactor.offload` and `reactor.OffloadError` (`src/hecate/reactor/offload.lua`), codec `internal/transfer.lua`; tests `tests/unit/offload_test.lua` (23 cases) and a case in `suspension_test.lua`. `test reactor`, `typecheck`, `lint`, `check-boundaries` pass locally (commit 69f82d4).
- Docs: README (status, scope, non-goals, API row), package `CLAUDE.md`, `pkg-reactor` agent scope, tested example `examples/hecate.reactor.offload.lua`, guide `website/en/how-to/offload-cpu-bound-work.md` (+ index), CHANGELOG. No benchmark: `offload` is a new path, not a change to a hot path. French page not written (the French tree does not mirror every how-to yet; `translator-fr` later).
- Reviews (pkg-reactor, api-reviewer, cross-platform-reviewer) and their fixes: blocker, a segmentation fault at exit when a cancelled caller's function still ran (luv closes the state with work in flight): `Reactor:run` now waits for every offloaded function (`context.offloads_in_flight`), with a child-process test `tests/integration/offload_exit_test.lua` that fails without the fix; `work` runs every step under `pcall` and gives the function a fresh environment per call (a polluted global used to hang every later call on the thread); error labels of the codec built only on failure and one `string.pack` per value (1M-entry encode 2.94 s -> 0.62 s); `OffloadError` annotated with `context.reason`/`traceback?`/`code?`; refused work raises `IoError`; stripped functions refused with a clear message; test timings shortened; micro-benchmark `reactor/offload`; how-to glossary links, OUTLINE, llms.txt. `check-boundaries` exempts `offload.lua` for `setmetatable` (pool-thread state has no `hecate.core`).

## Next steps

1. CI green on the three platforms for the review-fix commit; then tick the roadmap item, delete this file, mark the pull request ready and ask for the owner's review.

## Decisions taken (and where they are recorded)

- Five conservative choices recorded in OQ-119 (#177): plain tables cross through an own `string.pack` encoding (luv alone: 9 scalars, silently truncated); `OffloadError`; cancellation releases the caller and discards the result; no concurrency limit of its own; `require` uses the environment paths.
- Measured on luv 1.53.0 (scratch probe): per-thread states with stdlib and `require`; errors in the work function are swallowed by luv, so a worker wrapper must `pcall` and encode; upvalues are lost by the bytecode copy.

## Doubts and questions for the owner

- OQ-119 (6): the luv crash at exit is luv's defect; reporting it upstream is an outward action left to the owner.
- Not fixed (minor, recorded here): when a run fails and is torn down, `waiting` keeps the entry of a closed caller until the late result arrives (harmless: `wake_computation` ignores a dead computation).

## Commands to re-run

```sh
lua tools/run.lua setup-luals   # once per session: pinned LuaLS into spikes/luals
lua tools/run.lua typecheck     # required before every push (CI fails on any warning)
lua tools/run.lua test reactor
```
