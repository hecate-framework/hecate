# `hecate-test`

> xUnit test framework running inside the reactor: cases, suites, fixtures, assertions, in-process HTTP client, contract conformance, property-based testing, coverage.

| | |
|---|---|
| Module | `hecate.test` |
| Rock | `hecate-test` |
| Layer | Tooling |
| Roadmap phase | 3 |
| Status | alpha (in progress) — `Case` with the bootstrap assertions plus deep equality with a structural diff, `assert_near`, `assert_match`, `assert_error` (class and code), `assert_shape`, and a count of the assertions of each test; `Runner` (each test in its own reactor, scope and leak detection, containment of every failure, name filter) emitting an event stream; discovery of `*_test.lua`; reporters: console (one line per suite with a loading bar, colour, live redraw on a terminal), TAP 14, JUnit XML (`test.JUnitReporter`, written at the end of the run) and JSON lines for IDE adapters. Tags (`Case.tags`, `Case.test_tags`; runner options `tags`, `exclude_tags`). Targeting: runner option `cases` and `test.parse_arguments(args)` for the command line (`--filter`, `--case`, `--tag`, `--exclude-tag`, paths). Parametrised tests (`Case.test_parameters`, one test per entry named `Case.test_x[label]`). In-process HTTP client (`test.Client`). Fixtures: `test.boot(options, overrides)` boots an application with container overrides and returns a client and the application. Virtual clock (runner option `clock`, case field `clock`). Not yet: database fixtures, contract conformance, property-based testing, coverage, parallel workers |
| Lua | 5.5 (`lua >= 5.5, < 5.6`) |
| Depends on | [`core`](../core), [`reactor`](../reactor), [`log`](../log), [`schema`](../schema), [`kernel`](../kernel), [`openapi`](../openapi), [`json`](../json) |
| Used by | `cli` |
| Native code | none |
| Specification | [testing.md](../../docs/architecture/testing.md) |
| Decisions | [ADR 0008](../../docs/adr/0008-own-test-framework.md) |
| Agent | [`pkg-test`](../../.claude/agents/pkg-test.md) |
| Repository | read-only mirror `hecate-framework/hecate-test`, generated from this directory (ADR 0017) |

## Responsibilities

- discovery, runner, reporters
- per-test scope with leak detection
- assertions with structural diffs
- in-process client and contract conformance report
- property-based testing with shrinking from `schema` generators
- fixtures (container overrides, database transactions)
- coverage (LCOV)
- parallel workers

## Non-goals

- browser testing

## Standards and references

- xUnit patterns (Meszaros 2007)
- QuickCheck (Claessen & Hughes 2000)
- TAP 14
- JUnit XML

## Public API

```lua
local test = require("hecate.test")
```

| Name | Description |
|---|---|
| `test.Case(name)` | Declares a test case: a class (`hecate.core`) whose `test_*` methods are tests; optional `set_up`, `tear_down`, `set_up_case`, `tear_down_case`. Same names as the bootstrap harness. Fields set by `set_up_case` on its case-level instance are copied onto the instance of every test. |
| `self:assert_true/false/nil/not_nil(value, message?)` | Truthiness and nil checks. |
| `self:assert_equal(expected, actual, message?)` | `==` for non-tables, structural equality for tables, failure listing each difference by path. `assert_not_equal`, `assert_same` (identity). |
| `self:assert_near(expected, actual, tolerance?, message?)` | Absolute tolerance, default `1e-9`. |
| `self:assert_match(pattern, subject, message?)` | Lua pattern match. |
| `self:assert_error(fn, expectation?)` | Returns the raised value; the expectation is a pattern or `{ class, code, pattern, message }`. |
| `self:assert_shape(shape, value, message?)` | Shape of a table: predicates, nested shapes and literals. `test.of_type(name)` builds a type predicate. |
| `self:fail(message?)` | Fails unconditionally. |
| `test.AssertionFailure` | Error class (`hecate.test.AssertionFailure`) raised by a failed assertion; `context` has `location`, `expected`, `actual`, `differences`. |
| `test.Client(action)` | In-process HTTP client (OQ-139). `action` is what `Application:boot()` returns, or any function of a request. `:request(method, target, options?)` and `:get`, `:head`, `:post`, `:put`, `:patch`, `:delete`, `:options(target, options?)` serve a request through `http.serve_request` and return `response, failure` (`failure` is what the server would have logged, else nil). Options: `fields`, `content` (string), `json` (encoded, `Content-Type: application/json` unless set). Runs in the calling computation, so inside a test. |
| `test.Runner(options?)` | `plan(cases)` and `run(cases)`; options `reporter`, `filter` (pattern on the full test name), `clock` (`"real"` or `"virtual"`), `cases` (run only the cases with these names), `tags` (run only tests carrying one of them), `exclude_tags` (skip tests carrying any; wins). Tags come from the case field `tags` and the map `test_tags[method]`. Returns a `Summary` (`total`, `passed`, `failed`, `errored`, `assertions`, `ok`, `exit_code`, `results`, `suites`). Each test runs in a new `Reactor` and scope; a test that leaves coroutines running fails and they are cancelled. A suite is a test script: the file a case was loaded from by `test.load`, else the name of the case. |
| `Reporter:handle(event)` | The reporter interface: one method receiving the events of the run (see "Event stream"). |
| `test.ConsoleReporter(options?)` | One line per suite with a loading bar; options `write`, `color`, `live`, `width`, `bar_width`, `is_tty`, `getenv` (see "Console output"). |
| `test.TapReporter(write?)` | TAP version 14 with YAML diagnostics; the plan comes first. |
| `test.JsonLinesReporter(write?)` | The event stream as JSON lines, for IDE adapters (see "Event stream"). |
| `test.discover(directory)` | `---@async`. Sorted paths of `*_test.lua` under a directory. |
| `test.load(path)` | Loads a test file and returns its case; raises `test.LoadError`. |

## Console output

```text
Running 8 test(s)
PASS	tests/unit/alpha_test.lua (6 assertions, 0 failed, 0 errored) [...]
FAIL	tests/unit/beta_test.lua (4 assertions, 1 failed, 1 errored) [.FF.]
```

- One line per suite; dots stand for tests, assertions are counted in the line. `failed` and `errored`
  count tests (an assertion did not hold, or anything else was raised).
- The bar has at most 40 cells (`bar_width`) and never makes the line wider than the terminal
  (`width`, else `COLUMNS`, else 80); beyond that cells stand for several tests in proportion, and a cell
  is red when any test it stands for failed or errored. A long suite name keeps its tail.
- On a terminal the line of the running suite is redrawn in place (orange `TEST`, becoming `PASS` or
  `FAIL`). Anywhere else (pipes, CI, IDE consoles) each suite line is written once, completed, with no cursor control.
- Colour: `color` option, else `NO_COLOR` (off), `FORCE_COLOR` (on), else on for a terminal. Without
  colour a failed cell is drawn `F`. Escape sequences live in one module (`reporters/ansi.lua`).
- Failures and errors are listed with their details after the last suite.
- Whether stdout is a terminal is decided by `reactor.is_tty(1)` (libuv, every platform) and, on POSIX, `TERM` set and
  not `dumb`; pass `is_tty`, `live` or `color` to override it (OQ-138). The environment variable `HECATE_TEST_LIVE`
  (`1` or `0`) forces live redraw on or off, after the `live` option and before the terminal guess: an IDE console
  that runs in a pty looks like a terminal, so an IDE adapter selects the JSON-lines reporter, or sets `live = false`,
  `HECATE_TEST_LIVE=0` or `TERM=dumb`.

## Event stream

The runner delivers `run_started`, `suite_started`, `test_started`, `test_finished`, `suite_finished` and
`run_finished` events, as they happen, to `Reporter:handle`. The stream is the integration point for tools:
an IDE adapter, a CI annotator or the future JUnit XML reporter consume it and nothing else. A reporter only
writes through its `write` function; the framework writes nothing else to stdout.

`JsonLinesReporter` writes one JSON object per line (keys in canonical order, flushed per line, no colour, no
cursor control), schema version 1. Every object has `type`:

| `type` | Fields |
|---|---|
| `run_started` | `version` (1), `total` (tests), `suites` |
| `suite_started` | `suite` (name), `total` |
| `test_started` | `suite`, `test` (full name), `index` (1-based in the suite) |
| `test_finished` | `suite`, `test`, `index`, `case`, `status` (`passed`, `failed`, `errored`), `assertions`, `duration` (seconds), and when present `message`, `location`, `traceback`, `differences` |
| `suite_finished` | `suite`, `total`, `passed`, `failed`, `errored`, `assertions`, `duration` |
| `run_finished` | `total`, `passed`, `failed`, `errored`, `assertions`, `ok`, `exit_code`, `duration` |

New fields may be added to the objects without a new version; removing or renaming one raises `version`.
The last test of a case finishes after its `tear_down_case`, whose failure is reported on it. The exit
status of a command line runner is `Summary.exit_code` (0, or 1 when a test failed or errored).

Self-hosting: a test file may use `hecate.test` itself; return `core.finalise(Case)` so the bootstrap
harness can run it until it is deleted (ADR 0008).

## Layout (once implemented)

```text
src/hecate/test/init.lua   public entry point
tests/unit/  tests/integration/  tests/fixtures/
examples/    benchmarks/
```
