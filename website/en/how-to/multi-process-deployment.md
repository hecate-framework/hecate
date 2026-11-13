---
description: Serve a hecate application with several worker processes, stop it gracefully, replace its workers without downtime, and answer health checks with a plain route.
hecate: "0.x"
lua: "5.5"
order: 19
---

# Multi-process deployment, graceful shutdown and health checks

This guide shows how to serve an `Application` with several processes. It also shows how to stop it without losing
requests, replace its workers with new code, and answer the health checks of a container platform. It is written for
hecate 0.x and Lua 5.5. The design behind it is in [Multi-process serving](../explanation/multi-process-serving.md).

## Start several workers

To serve with several processes, set `workers` above 1. It is an option of `Application`, and also the
configuration key `server.workers` (`HECATE_SERVER__WORKERS`). The default is 1.

```lua
local app = hecate.Application({ routes = { orders }, workers = 4 })
```

The process you start becomes the [primary](../reference/glossary.md#concurrency): the process that starts and
supervises the workers. Its `serve()` starts that many [workers](../reference/glossary.md#concurrency). A worker is a
process with its own reactor that serves requests.

Each worker is the same program, started again with a worker role in its environment. A worker builds the same
application. Its own `serve()` detects the role and serves.

The `hello` example of the repository is such a program. `HELLO_WORKERS=4 lua main.lua` serves with four workers:

<!-- example: examples/hello/main.lua -->
```lua
-- Starts the hello API: `lua main.lua` (port from HELLO_PORT, default 8080;
-- worker processes from HELLO_WORKERS, default 1; Ctrl+C stops it
-- gracefully). Run it from this directory, with the Hecate packages on
-- `package.path`.
-- With HELLO_WORKERS above 1 this process is the primary, and the
-- supervisor starts this same script again for each worker (ADR 0023): a
-- worker builds the same application and `serve` detects its role.
package.path = "src/?.lua;src/?/init.lua;" .. package.path

local reactor = require("hecate.reactor")
-- Only for `kernel.supervisor.worker_role()`, not in the meta-module
-- `hecate`.
local kernel = require("hecate.kernel")
local log = require("hecate.log")
local hello = require("hello")

local port = tonumber(os.getenv("HELLO_PORT") or "") or 8080
local workers = math.tointeger(tonumber(os.getenv("HELLO_WORKERS") or "")) or 1
--- Logs each response on the standard error stream (the default logger):
--- the method, the path without the query string (the raw target can carry
--- secrets such as tokens), the status, the bytes sent and the duration.
---@param info hecate.http.ResponseInfo
local function log_response(info)
  local path = (info.target or "-"):match("^[^?]*")
  log.default():informational(("%s %s -> %d"):format(info.method or "-", path, info.status),
    { status = info.status, bytes = info.bytes, duration_ms = math.floor(info.duration * 1000 + 0.5) })
end

local app = hello.application({
  server = { host = "127.0.0.1", port = port, on_response = log_response },
  workers = workers, grace_timeout = 10,
})

-- `serve` logs the address it listens on, and returns once SIGINT or
-- SIGTERM has stopped it: the requests in flight finish within the grace
-- period (10 seconds here).
-- The role is read before `serve`, which takes it.
local primary = kernel.supervisor.worker_role() == nil
reactor.run(function() app:serve() end)
if primary then io.stdout:write("hello: stopped\n") end
```

### Errors are reported once

Before it starts any worker, the primary boots the application once. So a configuration error, a missing service or
a wrong route declaration is reported once, by the primary, not once per worker.

The primary also checks the `server` options before it starts anything.

### Crashed workers are restarted

The primary restarts a worker that exits. The delay before the restart starts at 0.1 seconds and doubles, up to
10 seconds.

A worker must report that it is ready within `ready_timeout` seconds (default 30). A worker that does not is killed
and counted as a crash.

After 5 crashes within 60 seconds, `serve` raises a `SupervisorError` with the reason `crash_loop`. With the option
`on_crash_loop = "degrade"`, the primary keeps restarting at the longest delay instead.

### How a worker is started

A worker starts from the `worker_command` option. By default, that is the interpreter, the main script and the
arguments of the primary.

Give `worker_command` when the program was not started as a script, for example when Lua is embedded.

## Choose the listening strategy

The [listening strategy](../reference/glossary.md#concurrency) says how the workers obtain connections. Set it with
`server.strategy` or with the `strategy` option:

| Value | Behaviour |
|---|---|
| `auto` (default) | `reuseport` where it is supported, `round_robin` otherwise: `round_robin` today |
| `round_robin` | the primary accepts each connection and hands it over to the next worker; works everywhere |
| `reuseport` | each worker accepts on its own socket; Linux only, with a luv release that has TCP `reuseport`, not published yet (OQ-43) |

In `round_robin`, the primary passes each accepted connection to a worker through the
[message pipe](../reference/glossary.md#concurrency) of that worker, a framed connection between the two processes.
That is the [hand-over](../reference/glossary.md#concurrency).

When you name `reuseport` and it is not supported, the primary logs a warning and uses `round_robin`. With `auto`,
the same choice is the documented default and logs no warning.

Nothing else in your code depends on the strategy.

## Stop gracefully

A graceful stop lets the requests in flight finish. On `SIGINT` or `SIGTERM`, `serve` stops accepting connections.
It lets the requests in flight finish for the [grace period](../reference/glossary.md#http), then cancels what
remains and returns.

The grace period is `server.grace_timeout` seconds (`HECATE_SERVER__GRACE_TIMEOUT`; default 30). The
`grace_timeout` option sets it too.

A second signal during the drain stops at once.

Who drains depends on the number of processes:

- With one process, the server drains its own requests.
- With workers, the primary sends each worker a `stop` message with the grace period. It kills those still running
  one second after the grace period.

A worker ignores `SIGINT` and `SIGTERM`. A terminal sends them to the whole process group, and only the primary
decides. So a plain `kill` (`SIGTERM`) on the process id of a worker does nothing.

### Stop without signals

The signals are watched by default. With `signals = false` (tests, embedding), stop the application yourself. Call
`app:shutdown(grace_timeout?)` from another computation.

### Fit the platform

Keep the grace period shorter than the stop timeout of your platform. `docker stop` waits 10 seconds by default,
Kubernetes 30.

> [!WARNING] Windows
> Windows never delivers `SIGTERM`. Only Ctrl+C (`SIGINT`) stops gracefully. A service manager that ends the primary
> with `TerminateProcess` gets no graceful shutdown. The workers see their message pipe close and drain with the
> default grace period.

## Replace the workers with new code

A rolling reload replaces the workers one at a time, with no worker missing from the rotation. Start it in one of
two ways:

- send `SIGHUP` to the primary;
- call `app:reload({ grace_timeout?, ready_timeout? })` from a computation of the primary.

For each worker, the primary does four steps:

1. It starts a fresh process from the same command, so the new process runs the code on disk now.
2. It waits until the fresh process is ready.
3. It adds the fresh process to the rotation.
4. It stops the old worker with the grace period.

The reload logs `reload_started`, then `reload_done` or `reload_failed`.

### When a reload fails or is refused

A replacement that exits or is not ready in time aborts the reload. The old worker keeps serving. The workers already
replaced stay replaced.

A second reload while one runs is refused. So is a reload during a shutdown. A refused reload logs a warning
(`reload_refused`). Called through `app:reload`, a refused or failed reload also raises a `SupervisorError`.

With one process, `SIGHUP` is ignored. On Windows it is not watched.

## Answer health checks

A container platform probes each instance to know whether it serves. hecate has no built-in health endpoint. A
health check is a plain route that answers `200`, as in the `hello` example:

```lua
local health = hecate.routes("health")
health:get("/health", {
  responses = { [200] = schema.object({ status = schema.string() }) },
  action = function() return { status = "ok" } end,
})
```

What it tells the platform:

- **The process serves requests.** With workers, the probe reaches whichever worker gets the connection, as any
  request does.
- **During a graceful shutdown**, the listener is closed. A new probe cannot connect, while the requests in flight
  finish. The platform sees the instance leave before it stops.

### What does not exist yet

- There is no readiness probe that reports a worker draining, or that checks a database or another dependency. An
  action can do the checks you need itself, bounded with `reactor.deadline`.
- There is no endpoint for the counters the primary keeps per worker (`Supervisor:counters()`, primary only).
- There is no `hecate serve --workers` command. The `cli` package is planned for Phase 3, and `Application` starts its
  workers itself.

## See also

- [Multi-process serving](../explanation/multi-process-serving.md): strategies, message pipe, limits.
- [Before going to production](before-going-to-production.md): workers, signals and the grace period.
- [Configure an application](configure-an-application.md): the `server.*` keys.
