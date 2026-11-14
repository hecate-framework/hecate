---
description: Serve a hecate application with several worker processes, stop it gracefully, replace its workers without downtime, and answer health checks with a plain route.
hecate: "0.x"
lua: "5.5"
order: 19
---

# Multi-process deployment, graceful shutdown and health checks

This guide shows how to serve an `Application` with several processes, stop it without losing requests, replace its
workers with new code, and answer the health checks of a container platform. It is written for hecate 0.x and
Lua 5.5. The design behind it is in [Multi-process serving](../explanation/multi-process-serving.md).

## Start several workers

Set `workers` above 1, as an option of `Application` or with the configuration key `server.workers`
(`HECATE_SERVER__WORKERS`; default 1). The process you start becomes the
[primary](../reference/glossary.md#concurrency). Its `serve()` starts that many
[workers](../reference/glossary.md#concurrency), each one the same program started again with a worker role in its
environment. A worker builds the same application, and its own `serve()` detects the role and serves.

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

Before it starts any worker, the primary boots the application once. A configuration error, a missing service or a
wrong route declaration is therefore reported once, by the primary, not once per worker. The primary also checks the
`server` options before it starts anything.

The primary restarts a worker that exits, after a delay that starts at 0.1 seconds and doubles up to 10 seconds. A
worker that does not report that it is ready within `ready_timeout` seconds (default 30) is killed and counted as a
crash. After 5 crashes within 60 seconds, `serve` raises a `SupervisorError` with the reason `crash_loop`; with the
option `on_crash_loop = "degrade"`, the primary keeps restarting at the longest delay instead.

A worker starts from the `worker_command` option, by default the interpreter, the main script and its arguments of
the primary. Give `worker_command` when the program was not started as a script, for example when Lua is embedded.

## Choose the listening strategy

`server.strategy` (or the `strategy` option) says how workers obtain connections:

| Value | Behaviour |
|---|---|
| `auto` (default) | the platform default: `round_robin` today |
| `round_robin` | the primary accepts each connection and hands it over to the next worker; works everywhere |
| `reuseport` | each worker accepts on its own socket; needs a luv version that does not exist yet (OQ-43) |

When the chosen strategy is not supported, the primary logs a warning and uses `round_robin`. Nothing else in your
code depends on the strategy.

## Stop gracefully

On `SIGINT` or `SIGTERM`, `serve` stops accepting connections and lets the requests in flight finish for the
[grace period](../reference/glossary.md#http): `server.grace_timeout` seconds (default 30;
`HECATE_SERVER__GRACE_TIMEOUT`), or the `grace_timeout` option. Then it cancels what remains and returns. A second
signal during the drain stops at once.

- With one process, the server drains its own requests.
- With workers, the primary sends each worker a `stop` message with the grace period, and kills those still running
  one second after it.
- A worker ignores `SIGINT` and `SIGTERM`: a terminal sends them to the whole process group, and only the primary
  decides. `kill` on the process id of a worker does nothing.

The signals are watched by default. With `signals = false` (tests, embedding), stop the application yourself with
`app:shutdown(grace_timeout?)` from another computation. Keep the grace period shorter than the stop timeout of your
platform: `docker stop` waits 10 seconds by default, Kubernetes 30.

> [!WARNING] Windows
> Windows never delivers `SIGTERM`. Only Ctrl+C (`SIGINT`) stops gracefully. A service manager that ends the primary
> with `TerminateProcess` gets no graceful shutdown; the workers see their message pipe close and drain with the
> default grace period.

## Replace the workers with new code

A rolling reload replaces the workers one at a time, with no worker missing from the rotation. Send `SIGHUP` to the
primary, or call `app:reload({ grace_timeout?, ready_timeout? })` from a computation of the primary. For each worker,
the primary starts a fresh process from the same command (so it runs the code on disk now), waits until it is ready,
adds it to the rotation, then stops the old one with the grace period.

- A replacement that exits or is not ready in time aborts the reload: the old worker keeps serving. The workers
  already replaced stay replaced.
- A second reload while one runs, or a reload during a shutdown, is refused with a warning.
- With one process, `SIGHUP` is ignored. On Windows it is not watched.

The reload logs `reload_started`, then `reload_done` or `reload_failed`.

## Answer health checks

hecate has no built-in health endpoint. A health check is a plain route that answers `200`, as in the `hello`
example:

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
- **During a graceful shutdown**, the listener is closed: a new probe cannot connect, while the requests in flight
  finish. The platform sees the instance leave before it stops.

What does not exist yet:

- no readiness probe that reports a worker draining, or checks a database or another dependency (an action can do the
  checks you need itself, bounded with `reactor.deadline`);
- no endpoint for the counters the primary keeps per worker (`Supervisor:counters()`, primary only);
- no `hecate serve --workers` command: the `cli` package is planned for Phase 3, and `Application` starts its workers
  itself.

## See also

- [Multi-process serving](../explanation/multi-process-serving.md): strategies, message pipe, limits.
- [Before going to production](before-going-to-production.md): workers, signals and the grace period.
- [Configure an application](configure-an-application.md): the `server.*` keys.
