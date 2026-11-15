<!-- Relay handoff note. Lives only on relay branches; deleted before review. -->
# Handoff

- roadmap_item: `test`: test framework, runner, in-process client, fixtures, contract conformance, reporters (TAP, JUnit XML), coverage (Phase 3)
- status: in-progress
- lock_until: 2026-11-15T10:40:18Z
- last_update: 2026-11-15T10:40:18Z

## Done

- Claimed the item. Owner instruction (2026-11-15): do not lock a multi-run item, so `lock_until` stays at the claim time (already expired) and other relay runs may resume it.

- Step 2 (console and events): the runner emits events (`run_started`, `suite_started`, `test_started`, `test_finished`, `suite_finished`, `run_finished`) to `Reporter:handle`; assertions are counted per test; console reporter with a loading bar per suite (colour, live redraw on a TTY, plain elsewhere); `JsonLinesReporter` for IDE adapters; TAP on the same events; golden files (plain, colour, live, TAP, JSON lines) and scaling tests. README, testing.md, CHANGELOG updated; OQ-138 recorded.

## Next steps

1. Read docs/architecture/testing.md, ADR 0008, the bootstrap harness (tools/harness/); write the tests first.
2. (done, steps 1 and 2) Core, runner, console, TAP and JSON-lines reporters.
3. Parametrise, tags and targeting, JUnit XML reporter (consume the event stream), leak detection, fake clock.
4. In-process client over the dispatch seam of OQ-78 (table `content` JSON-encoded or raise, T2), fixtures with container overrides.
5. Contract conformance report; property-based testing from schema types (OQ-96); coverage (LCOV); parallel workers.
6. Docs (README, website reference, CHANGELOG), roadmap tick.

## Decisions taken (and where they are recorded)

- Each test runs in its own `Reactor` (not one shared reactor): full isolation, and it prepares the virtual clock.
- A failing `tear_down_case` is reported on the last test of the case, so the TAP plan stays exact.

- Reporter interface is one method, `handle(event)`; events carry `type`; `test_finished` carries a `Result`. The last test of a case finishes after `tear_down_case`.
- A suite is the file a case was loaded from (`discovery.origin`, recorded by `test.load`), else the case name; consecutive cases of one suite are grouped.
- Dots are tests; `failed` and `errored` in a suite line count tests; assertions of `set_up_case`/`tear_down_case` are not counted. Counting wraps the assertion methods (one module-level counter set by the runner).
- Bar: at most 40 cells, shrunk by width; live lines reserve room for 3-digit assertion counts; without colour a failed cell is `F`; long names keep their tail.
- Live mode and colour default from terminal detection; JSON lines use `hecate.json` (native encoder, required lazily by that reporter only).

## Doubts and questions for the owner

- OQ-138 (no GitHub issue created yet): `luv` is confined to `reactor`, so TTY detection is a POSIX shell probe (`test -t 1`); a `reactor.is_tty` would be exact.
- The old `start/report/finish` reporter interface is replaced (breaking for step-1 users; none exist outside the package).

## Commands to re-run

```sh
lua tools/run.lua setup-luals   # once per session: pinned LuaLS into spikes/luals
lua tools/run.lua typecheck     # required before every push (CI fails on any warning)
lua tools/run.lua test test
```
