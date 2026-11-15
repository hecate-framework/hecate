<!-- Relay handoff note. Lives only on relay branches; deleted before review. -->
# Handoff

- roadmap_item: `test`: test framework, runner, in-process client, fixtures, contract conformance, reporters (TAP, JUnit XML), coverage (Phase 3)
- status: in-progress
- last_update: 2026-11-15T14:44:44Z

## Done

- Claimed the item. Owner instruction (2026-11-15): no lock in the handoff for this item (no `lock_until` line; do not add one), so other relay runs may resume it.

- Step 2 (console and events): the runner emits events (`run_started`, `suite_started`, `test_started`, `test_finished`, `suite_finished`, `run_finished`) to `Reporter:handle`; assertions are counted per test; console reporter with a loading bar per suite (colour, live redraw on a TTY, plain elsewhere); `JsonLinesReporter` for IDE adapters; TAP on the same events; golden files (plain, colour, live, TAP, JSON lines) and scaling tests. README, testing.md, CHANGELOG updated; OQ-138 recorded.

- Step 3a (commit fc44c2c): `HECATE_TEST_LIVE=0|1` read by the terminal resolution (after the `live` option, before the TTY guess); README, OQ-138 and CHANGELOG updated; a pipe probe test.

- Step 3b and 3c (this commit): the layout never exceeds the width (name shortened first down to 10 letters, then the bar down to 10 cells, then 1 cell, then the name down to a few letters; a live line keeps its reserved room and gives way when the figures outgrow it); test of a live suite of 1 234 567 assertions at widths 60, 80, 120; terminal probe tested on a pipe and under a pty (`script -qec`, skipped when `script` is missing or has another form).

- Step 4: `reactor.is_tty(fd)` (OQ-138); `test` drops the shell probe and the Windows exception. OQ-138 moved to Resolved in `docs/open-questions.md`; issue #215 closed.

- Step 5: `test.JUnitReporter` (consumes the event stream, writes one document at `run_finished`; suite = `testsuite`, test = `testcase`, XML 1.0 escaping, control characters become U+FFFD); leak detection already existed in the runner. Test in `reporters_test.lua`.

- Step 6: tags: `Case.tags`, `Case.test_tags[method]`, runner options `tags` (any of) and `exclude_tags` (wins); validated at `Runner:init`.

- Step 7: parametrised tests via `Case.test_parameters`.

- Step 8: virtual clock: runner option `clock`, case field `clock` (overrides); hooks and tests of the case share it. The README status line is refreshed (`alpha (in progress)`).

## Next steps

1. Targeting by name from the command line.
2. **Blocked on OQ-139 (issue #216):** in-process client over the dispatch seam of OQ-78 (`Application:boot()` action + `http.serve_request`; table `content` JSON-encoded or raise, T2), fixtures with container overrides. Needs the owner to allow `hecate.http` as a dependency of `test`.
3. Contract conformance report; property-based testing from schema types (OQ-96); coverage (LCOV); parallel workers.
4. Docs (README, website reference, CHANGELOG), roadmap tick.
5. **Windows testing phase (owner, by hand on a Windows VM; do not tick the item before the owner reports):** the console reporter in a real Windows terminal (Windows Terminal and `cmd.exe`): colour, live redraw (`live = true`, since the probe never turns it on there), width, the bar and the plain fallback in a pipe; the JSON-lines stream and TAP output with CRLF handling; `hecate.test` discovery paths with backslashes. Record the owner's findings here.

## Decisions taken (and where they are recorded)

- Each test runs in its own `Reactor` (not one shared reactor): full isolation, and it prepares the virtual clock.
- A failing `tear_down_case` is reported on the last test of the case, so the TAP plan stays exact.

- Reporter interface is one method, `handle(event)`; events carry `type`; `test_finished` carries a `Result`. The last test of a case finishes after `tear_down_case`.
- A suite is the file a case was loaded from (`discovery.origin`, recorded by `test.load`), else the case name; consecutive cases of one suite are grouped.
- Dots are tests; `failed` and `errored` in a suite line count tests; assertions of `set_up_case`/`tear_down_case` are not counted. Counting wraps the assertion methods (one module-level counter set by the runner).
- Bar: at most 40 cells, shrunk by width; live lines reserve room for 3-digit assertion counts; without colour a failed cell is `F`; long names keep their tail.
- Live mode and colour default from terminal detection; JSON lines use `hecate.json` (native encoder, required lazily by that reporter only).

## Doubts and questions for the owner

- OQ-139 (issue #216): may `test` depend directly on `hecate.http`? Recommended yes; blocks the in-process client.
- OQ-138 (issue #215, still open until `reactor.is_tty` lands; the owner agreed to both the explicit `HECATE_TEST_LIVE` switch and `reactor.is_tty(fd)`): `luv` is confined to `reactor`, so TTY detection is a POSIX shell probe (`test -t 1`); a `reactor.is_tty` would be exact.
- The old `start/report/finish` reporter interface is replaced (breaking for step-1 users; none exist outside the package).

## Commands to re-run

```sh
lua tools/run.lua setup-luals   # once per session: pinned LuaLS into spikes/luals
lua tools/run.lua typecheck     # required before every push (CI fails on any warning)
lua tools/run.lua test test
```
