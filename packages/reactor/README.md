# `hecate-reactor`

> The reactor over libuv (luv): coroutine scheduler, futures, structured concurrency, synchronisation primitives, timers, signals, processes, file system and thread-pool offloading.

| | |
|---|---|
| Module | `hecate.reactor` |
| Rock | `hecate-reactor` |
| Layer | 1 — Runtime |
| Roadmap phase | 1 |
| Status | specified — no code yet |
| Lua | 5.5 (`lua >= 5.5, < 5.6`) |
| Depends on | [`core`](../core) |
| Used by | `cli`, `hecate`, `http`, `kernel`, `log`, `mongodb`, `mysql`, `net`, `orm`, `postgresql`, `redis`, `sql`, `sqlite`, `sqlserver`, `test`, `websocket` |
| Native code | luv (libuv binding) |
| Specification | [concurrency.md](../../docs/architecture/concurrency.md) |
| Decisions | [ADR 0002](../../docs/adr/0002-libuv-via-luv.md), [ADR 0003](../../docs/adr/0003-transparent-structured-concurrency.md), [ADR 0004](../../docs/adr/0004-academic-vocabulary.md) |
| Agent | [`pkg-reactor`](../../.claude/agents/pkg-reactor.md) |
| Repository | read-only mirror `hecate-framework/hecate-reactor`, generated from this directory (ADR 0017) |

## Responsibilities

- scheduler resuming coroutines on libuv completions
- `fork`, `join`, `select`, `deadline`, `sleep`, `scope`, `detach`, `offload`
- `Future`, `Channel`, `Semaphore`, `Mutex`, `Monitor`, `Condition`
- cooperative cancellation (`CancellationError`) and `DeadlineExceeded`
- timers, signals, child processes, pipes, file-system operations as suspending calls
- worker process management primitives used by the kernel (OQ-8)
- virtual clock for tests

## Non-goals

- network protocols (see `net`)
- OS threads running Lua code

## Standards and references

- Schmidt, *Reactor* (1995)
- Hoare, *CSP* (1978)
- structured concurrency (Sústrik 2016; Smith 2018)

## Public API

*To be filled during implementation: list every exported class and function with a one-line
description, linking to the generated reference.*

## Layout (once implemented)

```text
src/hecate/reactor/init.lua   public entry point
tests/unit/  tests/integration/  tests/fixtures/
examples/    benchmarks/
csrc/        native sources
```
