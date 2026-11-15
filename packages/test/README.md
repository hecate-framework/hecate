# `hecate-test`

> xUnit test framework running inside the reactor: cases, suites, fixtures, assertions, in-process HTTP client, contract conformance, property-based testing, coverage.

| | |
|---|---|
| Module | `hecate.test` |
| Rock | `hecate-test` |
| Layer | Tooling |
| Roadmap phase | 3 |
| Status | alpha (step 1 of the roadmap item) — `Case` with the bootstrap assertions plus deep equality with a structural diff, `assert_near`, `assert_match`, `assert_error` (class and code), `assert_shape`; `Runner` (each test in its own reactor, scope and leak detection, containment of every failure, name filter); discovery of `*_test.lua`; console and TAP 14 reporters. Not yet: parametrisation, tags, JUnit XML and JSON reporters, fake clock, in-process client, fixtures, contract conformance, property-based testing, coverage, parallel workers |
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
| `test.Runner(options?)` | `plan(cases)` and `run(cases)`; options `reporter`, `filter` (pattern on `Case.test_name`). Returns a `Summary` (`total`, `passed`, `failed`, `errored`, `ok`, `results`). Each test runs in a new `Reactor` and scope; a test that leaves coroutines running fails and they are cancelled. |
| `test.ConsoleReporter(write?)`, `test.TapReporter(write?)` | Reporters (TAP version 14 with YAML diagnostics). |
| `test.discover(directory)` | `---@async`. Sorted paths of `*_test.lua` under a directory. |
| `test.load(path)` | Loads a test file and returns its case; raises `test.LoadError`. |

Self-hosting: a test file may use `hecate.test` itself; return `core.finalise(Case)` so the bootstrap
harness can run it until it is deleted (ADR 0008).

## Layout (once implemented)

```text
src/hecate/test/init.lua   public entry point
tests/unit/  tests/integration/  tests/fixtures/
examples/    benchmarks/
```
