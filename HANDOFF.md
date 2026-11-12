<!-- Relay handoff note. Lives only on relay branches; deleted before review. -->
# Handoff

- roadmap_item: `reactor` follow-up: specify then implement `offload` (Lua functions on the libuv thread pool), split from the Phase 1 item (OQ-27).
- status: in-progress
- lock_until: 2026-11-12T08:19:53Z
- last_update: 2026-11-12T06:49:53Z

## Done

- Claimed the item; draft pull request #176.
- Specification: `docs/architecture/concurrency.md` section "Offload"; OQ-119 with mirror issue #177.
- Implementation: `reactor.offload` and `reactor.OffloadError` (`src/hecate/reactor/offload.lua`), codec `internal/transfer.lua`; tests `tests/unit/offload_test.lua` (23 cases) and a case in `suspension_test.lua`. `test reactor`, `typecheck`, `lint`, `check-boundaries` pass locally.

## Next steps

1. README, website reference/how-to, CHANGELOG, benchmark if relevant.
2. Reviews (pkg-reactor, api-reviewer, cross-platform-reviewer, test-engineer), CI green on three platforms, tick the roadmap item, delete this file.

## Decisions taken (and where they are recorded)

- Five conservative choices recorded in OQ-119 (#177): plain tables cross through an own `string.pack` encoding (luv alone: 9 scalars, silently truncated); `OffloadError`; cancellation releases the caller and discards the result; no concurrency limit of its own; `require` uses the environment paths.
- Measured on luv 1.53.0 (scratch probe): per-thread states with stdlib and `require`; errors in the work function are swallowed by luv, so a worker wrapper must `pcall` and encode; upvalues are lost by the bytecode copy.

## Doubts and questions for the owner

## Commands to re-run

```sh
lua tools/run.lua setup-luals   # once per session: pinned LuaLS into spikes/luals
lua tools/run.lua typecheck     # required before every push (CI fails on any warning)
lua tools/run.lua test reactor
```
