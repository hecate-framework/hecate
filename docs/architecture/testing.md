# Testing (`hecate.test`)

Status: specification; decision in [ADR 0008](../adr/0008-own-test-framework.md) (Accepted).

## Goals

1. One idiom for testing the framework itself and applications built with it.
2. Tests run **inside the reactor**: code under test suspends transparently.
3. Contracts are verified automatically: every response produced in tests is checked
   against the route's declared schemas.
4. Fast feedback: unit tests of a package run in under a second.

## Vocabulary (xUnit)

*test case* (class whose `test_*` methods are tests), *test suite* (collection of
cases), *fixture* (set-up state), *assertion*, *runner*, *reporter*.

## Surface (illustrative)

```lua
local test = require "hecate.test"

local RouterTest = test.Case("RouterTest")

function RouterTest:set_up()      self.router = Router() end
function RouterTest:tear_down()   end

function RouterTest:test_static_path_wins_over_parameter()
  self.router:add("GET", "/users/me", "me")
  self.router:add("GET", "/users/{id}", "show")
  self:assert_equal("me", self.router:match("GET", "/users/me").route.action)
end

return RouterTest
```

## Features

| Feature | Description |
|---|---|
| Discovery | `tests/**/*_test.lua` returning a case or a suite |
| Lifecycle | `set_up`/`tear_down` per test, `set_up_case`/`tear_down_case` per case |
| Scope | each test runs in its own reactor scope; leaked coroutines fail the test |
| Assertions | equality (deep, with diff), errors (class + code), schema conformance, approximate numbers, pattern, table shape |
| Parametrisation | `test.parametrise(cases, fn)` producing named tests |
| Property-based testing | generators derived from `hecate.schema` types; shrinking (QuickCheck, Claessen & Hughes 2000) |
| HTTP client | in-process client hitting the kernel without sockets; optional real-socket mode |
| Contract conformance | in test mode, every response is validated against its declared schema; a report lists routes never exercised |
| Fixtures | container overrides (`test.boot`); database fixtures with transactional rollback per test, delivered by the `sql` item |
| Fakes | fake clock for `reactor` (virtual time for deadlines and sleeps) |
| Reporters | console, TAP 14, JUnit XML, JSON |
| Coverage | line coverage via debug hooks, LCOV output (`test.LineCoverage`, runner option `coverage`, `run_parallel` option `coverage`; the bootstrap harness implements the same until the migration: task `coverage`, `HECATE_TEST_COVERAGE`; thresholds of 90 % for `core`, `reactor`, `router` and `schema`, run nightly) |
| Leak detection | a test that leaves libuv handles open fails (the bootstrap harness: task `leaks`, `HECATE_TEST_LEAKS`; nightly) |
| Targeting | by file, case, test name pattern, tag (`slow`, `integration`, `database:postgresql`) |
| Parallelism | multiple worker processes, each with its own reactor; one process per test file; a planning pass gives the total first, then the events stream over a message pipe and are replayed live in path order (`test.run_parallel`) |

## Framework test policy

- Every package: unit tests (no I/O), integration tests when it performs I/O.
- Drivers: integration matrix against real servers (service containers).
- Parsers and codecs: fuzzing (C) and property tests (Lua).
- Suspension documentation check: functions annotated `---@async` are the ones observed
  to yield. `packages/reactor/tests/unit/suspension_test.lua` instruments `coroutine.yield`, runs each
  public function of `hecate.reactor` on a path where it has to wait, and compares with the tag read from
  the source; an untested tagged function must be in its justified allowlist.
- Cross-platform: the whole suite runs on Linux, macOS and Windows.

## Console output and IDE integration

The runner reports a run as a stream of events (`run_started`, `suite_started`, `test_started`,
`test_finished`, `suite_finished`, `run_finished`) delivered as they happen to a reporter
(`Reporter:handle`); reporters never read the results after the fact. A *suite* is a test script (the
file a case is loaded from; a case declared in code is a suite of its own name).

The console reporter writes one line per suite, `PASS`, `FAIL` or `TEST` (in progress) with the number
of assertions, failed and errored tests, and a loading bar with one cell per test. The bar is capped
(40 cells) and by the terminal width; beyond that, cells are scaled and a cell is red when any test it stands
for failed or errored. On a terminal the line is redrawn in place; elsewhere each suite line is written
once, completed, with no cursor control. Colour honours `NO_COLOR`, `FORCE_COLOR` and terminal detection
or an explicit option; escape sequences are confined to one module. Details of failures and errors are
printed after the last suite.

For IDE embedding, the JSON-lines reporter writes the same events as one JSON object per line (documented
schema, flushed per line, no colour, no cursor control); an adapter reads it, and so will the JUnit XML
reporter. The TAP reporter announces its plan first and reports on the same events. Reporters write only
through their `write` function, so standard output carries nothing but the reporter's output, and the exit
status is `Summary.exit_code`.

## Bootstrap harness

Before `hecate.test` exists, `tools/harness/` provides `Case`, `assert_*`, discovery and
TAP output with the same names (ADR 0008).
