# 0003 — Transparent, structured concurrency on coroutines

- **Status:** Accepted
- **Date:** 2026-10-11
- **Deciders:** project owner
- **Packages:** reactor and every package performing I/O
- **Related:** [concurrency.md](../architecture/concurrency.md)

## Context

Two styles were considered for asynchronous code: explicit (futures returned by every
I/O operation, `:await()` everywhere, "coloured" functions) and transparent (I/O
operations suspend the current coroutine internally; code reads sequentially).

## Decision

- **Transparent by default.** Any I/O operation called from a coroutine managed by the
  reactor suspends that coroutine and resumes it with the result. No `await` in user
  code. Functions are not coloured.
- **Explicit when intended**: `fork`, `join`, `select`, `deadline`, channels,
  semaphores, mutexes, monitors (vocabulary: ADR 0004).
- **Structured**: every forked computation belongs to a scope; a scope does not end
  before its children; cancellation propagates downwards; errors propagate upwards.
  Each HTTP request runs in its own scope.
- Calling a suspending operation outside a reactor-managed coroutine raises a clear
  error (no silent blocking).

## Consequences

- Shared mutable state can change across any suspending call. Documentation gets a
  dedicated chapter; the framework discourages module-level mutable state.
- Non-yieldable contexts (`table.sort` comparators, `string.gsub` callbacks, some
  metamethods called from C) cannot perform I/O; detected and reported with a clear error.

## Verification

Concurrency test suite in `reactor` (cancellation, error propagation, leaks); a
debug mode that reports coroutines suspended across scope exit.
