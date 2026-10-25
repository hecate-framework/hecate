---
description: Log structured records with hecate.log, keep a context on a logger, hide secrets and limit the volume.
hecate: "0.x"
lua: "5.5"
order: 7
---

# Log structured records

This guide shows how to write structured records with `hecate.log`. It is written for hecate 0.x
and Lua 5.5.

## Create a logger and write records

A `Logger` has a level (default `informational`), sinks and an optional context. A call below the
level builds no record. A sink that raises never fails the caller.

<!-- example: packages/log/examples/hecate.log.Logger.lua -->
```lua
-- A logger drops what is below its level, adds its context to every record and hands the rest to
-- its sinks.
local log = require("hecate.log")

local sink = log.MemorySink()
local logger = log.Logger({ level = "informational", sinks = { sink } }):with_context({ request = "r-1" })

logger:debug("not recorded")
logger:warning("slow query", { millis = 120 })
local record = sink:records()[1]
print(("%d %s %s %s"):format(#sink:records(), record.message, record.context.request, record.fields.millis))
-- Prints: 1 slow query r-1 120
```

The severities are the eight of RFC 5424, `emergency` to `debug`. `with_context(fields)` returns a
child logger, whose context is fixed. To tag every record of a request, including those logged by
computations it forks or detaches, wrap the work in `log.bind({ request_id = "r-1" }, fn)`: a logger
without a `context_provider` adds the bound fields to its records.

## Choose a sink

- `ConsoleSink({ output = ... })`: one human-readable line per record, control characters escaped.
- `JsonLinesSink({ output = ... })`: one JSON object per line.
- `FileSink({ path = ... })`: appends JSON lines to a file, synchronously; call `close()` at the end.
- `MemorySink({ capacity = ... })`: keeps records, for tests.

A sink is any object with a `write(record)` method that does not suspend. A logger hands each
record to all its sinks; `logger:failures()` counts the sinks that raised.

## Hide secrets

Wrap a value in `log.Secret`: no sink renders it (it shows as `[redacted]`), at any depth of a
record. The value stays reachable through `reveal()`. To protect fields by name instead, give the
logger `redact = { "password", "token" }`: the values of fields with these names (case-insensitive,
at any depth, in the fields and in the context) are wrapped in a `Secret` before any sink sees them.

<!-- example: packages/log/examples/hecate.log.Secret.lua -->
```lua
-- A secret is never rendered by a sink, whatever the depth of the field that holds it.
local log = require("hecate.log")

local lines = {}
local logger = log.Logger({ sinks = { log.JsonLinesSink({ output = function(line) lines[#lines + 1] = line end }) } })

logger:error("login failed", { user = "ada", password = log.Secret("hunter2") })
print(("%s %s"):format(lines[1]:find("hunter2", 1, true) == nil, lines[1]:find("[redacted]", 1, true) ~= nil))
-- Prints: true true
```

## Limit the volume

Wrap a sink in `log.LimitedSink({ sink = ..., sample = 0.1, rate = 100 })` to keep a fraction of the
records and at most `rate` per second (token bucket, `burst` capacity). Records at least as urgent
as `exempt` (default `warning`) always pass. `dropped()` counts what was discarded.

## Keep slow sinks off the request path

Wrap a sink in `log.AsyncSink({ sink = ..., capacity = 1024 })`. `write` only queues the record, so
it never suspends; a detached task writes to the target. When the queue is full the record is
dropped and counted (`dropped()`): back-pressure is loss, never waiting. `flush()` suspends until
what is queued has been written, and `close()` flushes and stops the task. Call `close()` before
the main computation ends: a drain task still waiting for records is a deadlock to the reactor.

<!-- example: packages/log/examples/hecate.log.AsyncSink.lua -->
```lua
-- An asynchronous sink queues records and writes them from a detached task: logging never waits
-- for the target. `close` flushes what is queued and stops the task.
local reactor = require("hecate.reactor")
local log = require("hecate.log")

reactor.run(function()
  local memory = log.MemorySink()
  local async = log.AsyncSink({ sink = memory, capacity = 128 })
  local logger = log.Logger({ sinks = { async } })

  logger:informational("first")
  logger:informational("second")
  local waiting = async:pending()
  async:close()
  print(("%d %d %d"):format(waiting, #memory:records(), async:dropped()))
end)
-- Prints: 2 2 0
```
