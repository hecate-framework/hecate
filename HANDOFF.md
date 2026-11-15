<!-- Relay handoff note. Lives only on relay branches; deleted before review. -->
# Handoff

- roadmap_item: `test`: test framework, runner, in-process client, fixtures, contract conformance, reporters (TAP, JUnit XML), coverage (Phase 3)
- status: in-progress
- lock_until: 2026-11-15T10:40:18Z
- last_update: 2026-11-15T10:40:18Z

## Done

- Claimed the item. Owner instruction (2026-11-15): do not lock a multi-run item, so `lock_until` stays at the claim time (already expired) and other relay runs may resume it.

## Next steps

1. Read docs/architecture/testing.md, ADR 0008, the bootstrap harness (tools/harness/); write the tests first.
2. Core: `hecate.test` Case (object model), assert_* with structural diffs, lifecycle, discovery, runner in a reactor scope, console and TAP reporters.
3. Parametrise, tags and targeting, JUnit XML and JSON reporters, leak detection, fake clock.
4. In-process client over the dispatch seam of OQ-78 (table `content` JSON-encoded or raise, T2), fixtures with container overrides.
5. Contract conformance report; property-based testing from schema types (OQ-96); coverage (LCOV); parallel workers.
6. Docs (README, website reference, CHANGELOG), roadmap tick.

## Decisions taken (and where they are recorded)

- Each test runs in its own `Reactor` (not one shared reactor): full isolation, and it prepares the virtual clock.
- A failing `tear_down_case` is reported on the last test of the case, so the TAP plan stays exact.

## Doubts and questions for the owner

none yet.

## Commands to re-run

```sh
lua tools/run.lua setup-luals   # once per session: pinned LuaLS into spikes/luals
lua tools/run.lua typecheck     # required before every push (CI fails on any warning)
lua tools/run.lua test test
```
