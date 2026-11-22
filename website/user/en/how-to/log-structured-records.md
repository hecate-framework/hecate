---
description: Log structured records with hecate.log, keep a context on a logger, hide secrets and limit the volume.
hecate: "0.x"
lua: "5.5"
order: 7
---

# Log structured records

This guide shows how to write structured records with `hecate.log`. It is written for hecate 0.x and Lua 5.5.

A record is a message with its severity and named fields, not a line of free text.

## Create a logger and write records

A `Logger` has three parts:

- a [severity](../reference/glossary.md#logging), the least urgent one it records (default `informational`);
- sinks, the objects that receive its records;
- an optional context, fields added to every record.

<!-- example: packages/log/examples/hecate.log.Logger.lua -->
```lua
-- A logger drops what is less urgent than its severity, adds its context to
-- every record and hands the rest to its sinks.
local log = require("hecate.log")

local sink = log.MemorySink()
local logger = log.Logger({ severity = "informational", sinks = { sink } }):with_context({ request = "r-1" })

logger:debug("not recorded")
logger:warning("slow query", { millis = 120 })
local record = sink:records()[1]
print(("%d %s %s %s"):format(#sink:records(), record.message, record.context.request, record.fields.millis))
-- Prints: 1 slow query r-1 120
```

The severities are the eight of RFC 5424, from `emergency` to `debug`. Each one is a method of the logger:
`logger:warning(message, fields?)`.

A call less urgent than the severity of the logger builds no record. A sink that raises never fails the caller.

## Add a context to every record

`with_context(fields)` returns a child logger. Its context is fixed: every record it writes carries `fields`.

To tag every record of a request, wrap the work in `log.bind(fields, fn)`. It binds the fields in the
[ambient context](../reference/glossary.md#concurrency), the values visible to a running computation and inherited by
the computations it forks or detaches. A logger without a `context_provider` adds the bound fields to its records:

```lua
local log = require("hecate.log")
local reactor = require("hecate.reactor")

local sink = log.MemorySink()
local logger = log.Logger({ sinks = { sink } })

reactor.run(function()
  log.bind({ request_id = "r-1" }, function()
    reactor.join(reactor.fork(function()
      logger:informational("forked work")
    end))
  end)
end)
print(sink:records()[1].context.request_id)
-- Prints: r-1
```

`log.bind` must run in a coroutine managed by the reactor, as here inside `reactor.run`.

## Choose a sink

| Sink | Writes |
|---|---|
| `ConsoleSink({ output = ... })` | one human-readable line per record, control characters escaped |
| `JsonLinesSink({ output = ... })` | one JSON object per line |
| `FileSink({ path = ... })` | JSON lines appended to a file, synchronously; call `close()` at the end |
| `MemorySink({ capacity = ... })` | nothing: it keeps records, for tests |

A sink is any object with a `write(record)` method that does not suspend.

A logger hands each record to all its sinks. `logger:failures()` counts how many times a sink raised while writing a
record.

## Hide secrets

Wrap a value in `log.Secret`. No sink renders it, at any depth of a record: it shows as `[redacted]`. The value stays
reachable through `reveal()`.

<!-- example: packages/log/examples/hecate.log.Secret.lua -->
```lua
-- A secret is never rendered by a sink, whatever the depth of the field
-- that holds it.
local log = require("hecate.log")

local lines = {}
local logger = log.Logger({ sinks = { log.JsonLinesSink({ output = function(line) lines[#lines + 1] = line end }) } })

logger:error("login failed", { user = "ada", password = log.Secret("hunter2") })
print(("%s %s"):format(lines[1]:find("hunter2", 1, true) == nil, lines[1]:find("[redacted]", 1, true) ~= nil))
-- Prints: true true
```

### Redact fields by name

To protect fields by name instead, give the logger `redact = { "password", "token" }`. The values of fields with
these names are wrapped in a `Secret` before any sink sees them. The match:

- ignores case;
- reaches up to 16 levels deep;
- covers the fields and the context.

The default logger (`log.default()`) already redacts the names of `log.DEFAULT_REDACT`:

`password`, `passwd`, `secret`, `client_secret`, `token`, `access_token`, `refresh_token`, `id_token`, `api_key`,
`apikey`, `x-api-key`, `private_key`, `authorization`, `proxy-authorization`, `cookie`, `set-cookie`, `session`,
`sessionid` and `csrf`.

Do not modify the list. To extend it, copy it and pass the copy to a logger of your own:

```lua
local names = table.move(log.DEFAULT_REDACT, 1, #log.DEFAULT_REDACT, 1, {})
names[#names + 1] = "ssn"
local logger = log.Logger({ redact = names })
```

A plain `Logger` without `redact` redacts nothing.

### What redaction does not cover

Redaction is by exact field name. It never covers free text. A secret written into a message is printed, as in
`logger:error("login failed for " .. token)`. Pass it as a field instead.

## Limit the volume

Wrap a sink in `log.LimitedSink({ sink = ..., sample = 0.1, rate = 100 })`:

- `sample` keeps a fraction of the records;
- `rate` forwards at most that many records per second (token bucket, `burst` capacity).

Records at least as urgent as `exempt` (default `warning`) always pass. `dropped()` counts what was discarded.

## Keep slow sinks off the request path

Wrap a sink in `log.AsyncSink({ sink = ..., capacity = 1024 })`. `write` only queues the record, so it never
suspends. A drain computation writes the records to the target.

<!-- example: packages/log/examples/hecate.log.AsyncSink.lua -->
```lua
-- An asynchronous sink queues records and writes them from a drain
-- computation: logging never waits for the target. `close` flushes what is
-- queued and stops the drain computation.
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

When the queue is full, the record is dropped and counted (`dropped()`): back-pressure is loss, never waiting.

- `flush()` suspends until what is queued has been written.
- `close()` flushes, then stops the drain computation.

Call `close()` before the main computation ends. A drain computation still waiting for records is a deadlock to the
reactor.

## See also

- [Configure an application](configure-an-application.md): the `logging.*` keys.
- [Before going to production](before-going-to-production.md): logging and redaction in a deployment.
- Reference: [`hecate.log`](../reference/log/index.md)
