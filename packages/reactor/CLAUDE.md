# Agent context — `hecate.reactor`

You are working inside `packages/reactor`. Read the root `CLAUDE.md` first; this file adds
package-specific context. Specialist agent: `pkg-reactor`.

## Purpose

The reactor over libuv (luv): coroutine scheduler, futures, structured concurrency, synchronisation primitives, timers, signals, processes, file system.

## Read before changing anything

- Specification: `docs/architecture/concurrency.md`
- Decisions: `docs/adr/0002-libuv-via-luv.md`, `docs/adr/0003-transparent-structured-concurrency.md`, `docs/adr/0004-academic-vocabulary.md`
- Glossary: `docs/glossary.md` · Coding standards: `docs/architecture/coding-standards.md`
- This package's `README.md` (scope, dependencies, status)

## Boundaries

- Allowed dependencies: `hecate.core`.
  Anything else requires an ADR; `check-boundaries` fails otherwise.
- Native code: luv (libuv binding).
- Out of scope: network protocols (see `net`); OS threads running Lua code.
- If your task needs a change in another package, stop and describe the needed change
  instead of making it (unless the task explicitly spans packages).

## Invariants (must hold after every change)

- only this package requires `luv`
- a scope never completes before its children
- calling a suspending operation outside a managed coroutine raises immediately
- no callback is ever exposed to user code
- cancellation runs `<close>` handlers

## Test strategy

- structured-concurrency suite (cancellation, error propagation, nested scopes)
- leak detection of coroutines and libuv handles
- stress: 10 000 concurrent coroutines on every platform
- virtual-time tests for deadlines

Plus, for every change: unit tests for public behaviour, LuaLS annotations on public API
(`---@async` on anything that may suspend), README "Public API" section updated.

## Known pitfalls

- yield across C boundaries (`table.sort`, `string.gsub` callbacks) must fail with a clear error
- Windows: signals and pipes differ; isolate behind the same API
- never resume a coroutine from inside a libuv callback stack without the scheduler

## Standards

- Schmidt, *Reactor* (1995)
- Hoare, *CSP* (1978)
- structured concurrency (Sústrik 2016; Smith 2018)
