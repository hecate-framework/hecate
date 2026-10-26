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
| Fixtures | container overrides, database fixtures with transactional rollback per test |
| Fakes | fake clock for `reactor` (virtual time for deadlines and sleeps) |
| Reporters | console, TAP 14, JUnit XML, JSON |
| Coverage | line coverage via debug hooks, LCOV output (the bootstrap harness implements it: task `coverage`, `HECATE_TEST_COVERAGE`; thresholds of 90 % for `core`, `reactor`, `router` and `schema`, run nightly) |
| Leak detection | a test that leaves libuv handles open fails (the bootstrap harness: task `leaks`, `HECATE_TEST_LEAKS`; nightly) |
| Targeting | by file, case, test name pattern, tag (`slow`, `integration`, `database:postgresql`) |
| Parallelism | multiple worker processes, each with its own reactor |

## Framework test policy

- Every package: unit tests (no I/O), integration tests when it performs I/O.
- Drivers: integration matrix against real servers (service containers).
- Parsers and codecs: fuzzing (C) and property tests (Lua).
- Suspension documentation check: functions annotated `---@async` are the ones observed
  to yield, measured by an instrumented run of the test suite.
- Cross-platform: the whole suite runs on Linux, macOS and Windows.

## Bootstrap harness

Before `hecate.test` exists, `tools/harness/` provides `Case`, `assert_*`, discovery and
TAP output with the same names (ADR 0008).
