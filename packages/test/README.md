# `hecate-test`

> xUnit test framework running inside the reactor: cases, suites, fixtures, assertions, in-process HTTP client, contract conformance, property-based testing, coverage.

| | |
|---|---|
| Module | `hecate.test` |
| Rock | `hecate-test` |
| Layer | Tooling |
| Roadmap phase | 3 |
| Status | specified — no code yet |
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

*To be filled during implementation: list every exported class and function with a one-line
description, linking to the generated reference.*

## Layout (once implemented)

```text
src/hecate/test/init.lua   public entry point
tests/unit/  tests/integration/  tests/fixtures/
examples/    benchmarks/
```
