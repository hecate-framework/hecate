---
title: Concurrency in hecate
description: How forked computations, futures and scopes fit together.
hecate: "0.x"
lua: "5.5"
order: 2
---

hecate runs many **coroutines** on one **reactor**. You never write callbacks: a
suspending call such as `sleep` pauses the running coroutine and lets the others run.

## The three ideas

- A **future** is a placeholder for a value that a computation will produce.
- `fork` starts a computation and returns its future.
- A **scope** owns the computations forked inside it and never completes before them.

### Why structured?

When a scope ends, every computation forked inside has either completed or been
cancelled. Nothing is left running behind your back.

> Cancellation is cooperative: it is delivered at the next suspension point, and
> `<close>` handlers run.

| Operation | Suspends | Returns |
|---|---|---|
| `fork(fn)` | no | a future |
| `join(...)` | yes | the values of the futures |
| `sleep(s)` | yes | nothing |

See the [reference for `sleep`](../reference/sleep.md#syntax) for the exact contract, or
go back to the [guide index](index.md).

## Callouts

> [!NOTE]
> A note carries background information.

> [!TIP]
> A tip suggests a better way, for example `reactor.deadline` instead of a manual timer.

> [!WARNING]
> A warning names a consequence that is easy to miss.

> [!CAUTION] Data loss
> A danger names a consequence that cannot be undone.
