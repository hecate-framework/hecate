# 0002 — libuv, through luv, as the I/O foundation

- **Status:** Accepted
- **Date:** 2026-10-11
- **Deciders:** project owner
- **Packages:** reactor, net, (indirectly) everything performing I/O
- **Related:** [concurrency.md](../architecture/concurrency.md), OQ-1, OQ-8

## Context

Lua has no concurrency primitives besides coroutines and no non-blocking I/O in its
standard library. Targets are Linux, macOS and Windows. Candidates: libuv (via luv),
cqueues (no Windows), a custom C core over epoll/kqueue/IOCP/io_uring.

## Options considered

1. **luv** (Apache-2.0): mature libuv binding used by Neovim and Luvit; packaged for Lua
   5.5 by some distributions (e.g. Alpine edge `lua5.5-luv`). Cross-platform, thread
   pool, timers, signals, processes, pipes, TTY, filesystem.
2. **cqueues**: elegant, but Linux/BSD/macOS only.
3. **Custom C core**: maximal control, years of work, three I/O models to maintain.

## Decision

Option 1. `hecate.reactor` is the only package allowed to `require "luv"`. Every other
package reaches the operating system through `hecate.reactor` and `hecate.net`.

## Consequences

- Windows is supported from the start.
- luv's callback API is wrapped once, in `reactor`, into suspending operations.
- If luv lags on Lua 5.5 for a platform, we contribute upstream first, fork second
  (OQ-1).
- libuv's thread pool is the standard way to run blocking work (SQLite, file system,
  CPU-heavy hashing).

## Verification

Linter rule: `require "luv"` outside `packages/reactor` fails CI (`check-boundaries`).
