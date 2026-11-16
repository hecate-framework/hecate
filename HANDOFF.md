<!-- Relay handoff note. Lives only on relay branches; deleted before review. -->
# Handoff

- roadmap_item: `test`: test framework, runner, in-process client, fixtures, contract conformance, reporters (TAP, JUnit XML), coverage (Phase 3)
- status: in-progress
- last_update: 2026-11-16T22:51:40Z

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

- Step 9: `test.Client` (OQ-139 resolved by the owner: `hecate.http` is a dependency of `test`; rockspec and package CLAUDE.md updated). Minimal on purpose: no route-coverage or conformance yet (owner: keep it simple, add by usage).

- Step 10: targeting: runner option `cases`; `hecate.test.selection` (`test.parse_arguments`) parses `--filter`, `--case`, `--tag`, `--exclude-tag`, paths. No command runs it yet (the `cli` package will call it). Tests in `selection_test.lua`.

- Step 11: fixtures: `test.boot(options, overrides)` (`fixture.lua`): wraps `validate` of the container to apply overrides after the modules bound their services. The dependency of `test` on `hecate.container` was planned by `container.md` and `testing.md` (no open question). Tests in `fixture_test.lua`.

- Step 12: generators (`generate.lua`): `test.generate`, `test.Generator`, from `to_json_schema()`, SplitMix64 seed. Tests in `generate_test.lua` (30 schemas x 60 seeds validated by `schema:validate`; recursion through `schema.of`).

- Step 13: property runner (`property.lua`): `test.check_property`, `Case:assert_property`; structural shrinking filtered by `schema:validate`. Known limit: integers shrink toward zero, one step at a time near a far bound (`max_shrinks`, default 1000). Tests in `property_test.lua`.

- Step 14: invalid values (`invalid.lua`): `test.generate_invalid`, `Generator:next_invalid`; candidates verified by `schema:validate` (exactly one violation), the expectation is the actual violation. Tests in `invalid_test.lua`. CI of steps 1 to 13 is green on the three platforms.

- Step 15: contract conformance: `test.boot` validates responses by default and returns a `RouteCoverage` (`coverage.lua`; matches through `application.router`, routes known from `application.entries`). Not done: a failure on a response whose status or media type the route does not declare (the kernel validates only the schema of a declared status); decide with the owner whether that belongs here or in `kernel`.

- Step 16: docs: `website/en/how-to/test-an-application.md`, OUTLINE, how-to index, `llms.txt` regenerated (no change); examples `hecate.test.boot` and `hecate.test.check_property` tested by `examples_test.lua`.

- Step 17: parallel runs (owner chose option A: worker processes split by file, off by default, `--jobs`): `parallel.lua`, `test.run_parallel`; workers started with `reactor.run_process` print one JSON line behind a marker; replay in path order; load failures and dead workers become errored suites. Tests in `parallel_test.lua`. LCOV needs nothing (bootstrap `coverage` task already exists; owner confirmed no open question).

- Windows testing, first findings (owner, fresh Windows x64, 2026-11-15 and 16): rows A, B, C of `packages/test/manual/README.md` ok in a Windows Terminal PowerShell tab and in `cmd.exe` (colours, bar, width; the stack trace is not wrapped to the width, accepted). Row D: the JSON lines are valid, but the accents were garbled in the file because the redirection was made from PowerShell (to redo with `cmd /c` or in `cmd.exe`). Accents show as `h├-llo` in both consoles: UTF-8 bytes read in code page 437 (to retest after `chcp 65001`). Owner confirmed (2026-11-16): the live redraw of row B works in both windows, and the garbled accents are accepted as the console code page (437), not a defect. Rows E to J, and row D redone with a clean redirect, not run yet. Setup findings: `winget` failed on the `msstore` source (use `--source winget`); the `luv` rock built through CMake needs `cmake_generator = "Ninja"` in the LuaRocks configuration (LuaRocks defaults to MinGW) and must run in the x64 Native Tools window; the procedure is corrected. Doubt: `bootstrap.ps1` could write that setting itself (CI on `windows-latest` builds `luv` without it, with another generator found on the runner); not changed, because the bootstrap hash is part of the CI cache keys.

- Windows testing phase done (owner, fresh Windows x64, 2026-11-16): rows A to J of `packages/test/manual/README.md` pass in Windows Terminal (PowerShell) and `cmd.exe`. Findings: live redraw is on by default in a real terminal and off when redirected (as designed, `reactor.is_tty`); redirected reports have CRLF line ends (text-mode stdout, documented, not changed); accents garbled only by code page 437 (documented); PowerShell 5.1 `>` writes UTF-16 (documented); suite names mixed `/` and `\` on Windows: fixed (`discovery.display_path`, test first). The stack trace of an error is not wrapped to the width (accepted).

- Step 17: the how-to page documents `test.run_parallel` (checked on the demo directory: same totals as a sequential run). Coverage: the spec makes the bootstrap harness the implementation of line coverage (task `coverage`), so `hecate.test` has none of its own yet.

- Step 18: `pattern` generation (`pattern_text.lua`, parses the ECMA form of the translation; tests in `generate_test.lua`, `invalid_test.lua`, `pattern_text_test.lua`). Roadmap: `cli` pointer and a new `test` item for the migration of the repository's tests (owner decisions of 2026-11-16: `core.finalise` at the end of cases; the `tools/CLAUDE.md` rule relaxed for `tools/tests`).

- Step 19: line coverage (`line_coverage.lua`): `test.LineCoverage`, runner option `coverage`, `run_parallel` option `coverage` (workers send hits as JSON, merged by the coordinator). Tests in `line_coverage_test.lua` (fixtures `tests/fixtures/coverage/`). The executable-line heuristic is a copy of `tools/lib/coverage.lua`; the migration item removes the duplicate. Owner decision (2026-11-16): the self-test solution is the complete one (pinned release plus current checkout), recorded in the migration item.

- Step 20: CI failed on step 19 because `.gitignore` ignores `coverage/` and swallowed the new fixture folder: renamed to `fixtures/line_coverage/` (lesson: after adding fixtures, run `git status --short --ignored` on the package). Generated reference: `test` added to `DEFAULT_PACKAGES` (doc package, one name) and to `.gitignore`; two page-name collisions fixed. French page written by `translator-fr`.

- Step 23: the medium findings D1 to D15 handled (statuses in the report); found while testing: the runner tests of steps 5 to 14 for M2, D3, D9 and the empty run had never been inserted (a replace that matched nothing); now present and passing. New finding N1: a test cannot call `Runner:run` (a reactor cannot start inside another), which the migration item must solve before the runner tests move. Deferred: D11 (terminal size needs a `reactor` function over `uv.tty_get_winsize`; owner decision), the lows.
- Step 22: the majors of the review are fixed (M1 to M4, M6 to M9; M5 declined by the owner as not useful), D7 (unused dependencies) and the glossary rows `worker`/`primary`; the parallel run now plans first and streams events live over a message pipe, replayed in path order (owner: required). Remaining findings (medium and low) to triage; the status column of the report is the list.
- Step 21: `/review-package test` by eight reviewers: `docs/reviews/test-review-package.md` (9 major, 15 medium, 9 low; M1 verified by a probe). No code changed yet.

## Next steps

0. Triage the low findings (L1 to L9) of `docs/reviews/test-review-package.md`; D11 waits for an owner decision (a `reactor.tty_size`). Then the final read, the roadmap tick and the review request.
1. **Required (owner, 2026-11-16, not optional): live output during a parallel run** (plan of all files first, then events streamed and replayed in path order). Not part of this item: the command-line entry point, the timeout, the leak check and the thresholds come with the migration item (roadmap).
2. Docs (owner: yes to both): run `gen-reference` for `test` and check the page; the French translation of the how-to page (`translator-fr`); a final read once the rest lands; then the roadmap tick and the review request.

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
