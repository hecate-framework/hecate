<!-- Relay handoff note. Lives only on relay branches; deleted before review. -->
# Handoff

- roadmap_item: `test`: test framework, runner, in-process client, fixtures, contract conformance, reporters (TAP, JUnit XML), coverage (Phase 3)
- status: in-progress
- last_update: 2026-11-15T10:40:18Z

## Done

- Claimed the item. Owner instruction (2026-11-15): no lock in the handoff for this item (no `lock_until` line; do not add one), so other relay runs may resume it.

- Step 2 (console and events): the runner emits events (`run_started`, `suite_started`, `test_started`, `test_finished`, `suite_finished`, `run_finished`) to `Reporter:handle`; assertions are counted per test; console reporter with a loading bar per suite (colour, live redraw on a TTY, plain elsewhere); `JsonLinesReporter` for IDE adapters; TAP on the same events; golden files (plain, colour, live, TAP, JSON lines) and scaling tests. README, testing.md, CHANGELOG updated; OQ-138 recorded.

## Next steps

1. Read docs/architecture/testing.md, ADR 0008, the bootstrap harness (tools/harness/); write the tests first.
2. (done, steps 1 and 2) Core, runner, console, TAP and JSON-lines reporters.
3. **Console follow-ups (owner-accepted, 2026-11-15), first thing of the next run, tests first:**
   a. (done) Explicit live switch for IDE consoles that run in a pty (indistinguishable from a terminal): `HECATE_TEST_LIVE=0` (and `1`) is read by the terminal resolution, after the `live` option and before the TTY guess; document in the README (an IDE adapter selects the JSON-lines reporter, or sets `live = false`, `HECATE_TEST_LIVE=0` or `TERM=dumb`) and add it to OQ-138 as a second point.
   b. Layout: the line never exceeds the width. The bar absorbs the overflow (minimum about 10 cells) and the suite name is shortened first; a test with a suite of 1000 or more assertions in live mode comes first; no fixed reserve of three digits.
   c. Test the terminal probe: under a pty (`script`, skipped when missing) live redraw; on a pipe, plain output with no escape codes (this runs on the three CI platforms).
4. Parametrise, tags and targeting, JUnit XML reporter (consume the event stream), leak detection, fake clock.
5. In-process client over the dispatch seam of OQ-78 (table `content` JSON-encoded or raise, T2), fixtures with container overrides.
6. Contract conformance report; property-based testing from schema types (OQ-96); coverage (LCOV); parallel workers.
7. Docs (README, website reference, CHANGELOG), roadmap tick.
8. **`reactor.is_tty(fd)`** (OQ-138, agreed): small step in `reactor` (over `uv.guess_handle`, tests on a pipe and a pty), then `test` drops the shell probe and the Windows exception; resolve OQ-138 and close #215 in that pull request. Do it before the `cli` item.
9. **Windows testing phase (owner, by hand on a Windows VM; do not tick the item before the owner reports):** the console reporter in a real Windows terminal (Windows Terminal and `cmd.exe`): colour, live redraw (`live = true`, since the probe never turns it on there), width, the bar and the plain fallback in a pipe; the JSON-lines stream and TAP output with CRLF handling; `hecate.test` discovery paths with backslashes. Record the owner's findings here.

## Decisions taken (and where they are recorded)

- Each test runs in its own `Reactor` (not one shared reactor): full isolation, and it prepares the virtual clock.
- A failing `tear_down_case` is reported on the last test of the case, so the TAP plan stays exact.

- Reporter interface is one method, `handle(event)`; events carry `type`; `test_finished` carries a `Result`. The last test of a case finishes after `tear_down_case`.
- A suite is the file a case was loaded from (`discovery.origin`, recorded by `test.load`), else the case name; consecutive cases of one suite are grouped.
- Dots are tests; `failed` and `errored` in a suite line count tests; assertions of `set_up_case`/`tear_down_case` are not counted. Counting wraps the assertion methods (one module-level counter set by the runner).
- Bar: at most 40 cells, shrunk by width; live lines reserve room for 3-digit assertion counts; without colour a failed cell is `F`; long names keep their tail.
- Live mode and colour default from terminal detection; JSON lines use `hecate.json` (native encoder, required lazily by that reporter only).

## Doubts and questions for the owner

- OQ-138 (issue #215, still open until `reactor.is_tty` lands; the owner agreed to both the explicit `HECATE_TEST_LIVE` switch and `reactor.is_tty(fd)`): `luv` is confined to `reactor`, so TTY detection is a POSIX shell probe (`test -t 1`); a `reactor.is_tty` would be exact.
- The old `start/report/finish` reporter interface is replaced (breaking for step-1 users; none exist outside the package).

## Commands to re-run

```sh
lua tools/run.lua setup-luals   # once per session: pinned LuaLS into spikes/luals
lua tools/run.lua typecheck     # required before every push (CI fails on any warning)
lua tools/run.lua test test
```
