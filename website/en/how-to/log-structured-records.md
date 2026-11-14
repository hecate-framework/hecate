---
description: Log structured records with hecate.log, keep a context on a logger, hide secrets and limit the volume.
hecate: "0.x"
lua: "5.5"
order: 7
---

# Log structured records

`hecate.log` writes records, not free text. A record has a severity, a message, structured fields and a context, and a
sink decides how to render it. Use it to log in a form that people and machines can both read. This guide is written
for hecate 0.x and Lua 5.5.

## Create a logger and write records

A `Logger` has three parts: a severity, a list of sinks and an optional context.

- The severity is the least urgent severity it records. The default is `informational`. A call below it builds no
  record.
- The sinks receive the records.
- The context is a table of fields added to every record.

A sink that raises never fails the caller. The logger counts the failure instead.

The example drops a `debug` call and records a `warning`:

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

The severities are the eight of RFC 5424: `emergency`, `alert`, `critical`, `error`, `warning`, `notice`,
`informational` and `debug`. Each one is a method of the logger: `logger:warning(message, fields?)`.

### Keep a context on a logger

`with_context(fields)` returns a child logger. Its context is the context of the parent extended with `fields`, and it
is fixed. The child shares the sinks of its parent.

### Tag every record of a request

A child logger must be passed to the code that uses it. To tag every record of a request without passing a logger,
bind the fields in the ambient context:

```lua
log.bind({ request_id = "r-1" }, function()
  -- every record logged here, and by the computations forked or
  -- detached here, carries request_id
end)
```

A logger without a `context_provider` adds the bound fields to its records. Its own context wins over them. `log.bind`
runs inside a managed coroutine.

## Choose a sink

A sink is where records go. Four sinks come with the package:

- `ConsoleSink({ output = ... })`: one human-readable line per record, control characters escaped. `output` is a
  function that receives each line, newline included.
- `JsonLinesSink({ output = ... })`: one JSON object per line.
- `FileSink({ path = ... })`: appends JSON lines to a file, synchronously. Call `close()` at the end.
- `MemorySink({ capacity = ... })`: keeps records in memory, for tests. Without `capacity` it is unbounded.

You can write your own. A sink is any object with a `write(record)` method that does not suspend.

A logger hands each record to all its sinks. `logger:failures()` counts the sinks that raised.

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

### Protect fields by name

To protect fields by name instead, give the logger `redact = { "password", "token" }`. Before any sink sees the
record, the values of the fields with these names are wrapped in a `Secret`. The names are matched case-insensitively,
in the fields and in the context, up to 16 levels deep in plain tables.

The default logger, `log.default()`, already does so with `log.DEFAULT_REDACT`:

- `password`, `passwd`, `secret`, `client_secret`;
- `token`, `access_token`, `refresh_token`, `id_token`;
- `api_key`, `apikey`, `x-api-key`, `private_key`;
- `authorization`, `proxy-authorization`;
- `cookie`, `set-cookie`, `session`, `sessionid`, `csrf`.

Do not modify this list. To extend it, copy it and pass the copy to a logger of your own:

```lua
local names = table.move(log.DEFAULT_REDACT, 1, #log.DEFAULT_REDACT, 1, {})
names[#names + 1] = "ssn"
local logger = log.Logger({ redact = names })
```

### Know what redaction does not cover

A plain `Logger` without `redact` redacts nothing.

Redaction is by exact field name. It never covers free text. A secret written into a message, as in
`logger:error("login failed for " .. token)`, is printed. Pass it as a field instead.

## Limit the volume

`log.LimitedSink` wraps a sink and drops part of the records that are less urgent than `exempt`:

```lua
local limited = log.LimitedSink({ sink = sink, sample = 0.1, rate = 100 })
```

It works in two steps.

- `sample` is the fraction, in (0, 1], of the other records that is kept. The default is 1.
- `rate` is the most other records forwarded per second, by a token bucket whose capacity is `burst` (default `rate`,
  at least 1). Without `rate` there is no limit.

Records at least as urgent as `exempt` (default `warning`) always pass. `dropped()` counts what was discarded.

## Keep slow sinks off the request path

`log.AsyncSink({ sink = ..., capacity = 1024 })` wraps a sink so that logging never waits for it. `write` only queues
the record, so it never suspends. A drain computation writes the queued records to the target. It starts at the first
`write`, which must run inside a reactor.

The example logs two records, then closes the sink:

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

Three methods control the queue:

- `flush()` suspends until what is queued has been written;
- `close()` flushes, stops the drain computation and closes the target;
- `dropped()` counts the records lost because the queue was full.

When the queue is full, the record is dropped and counted. Back-pressure is loss, never waiting. `capacity` defaults
to 1024.

Call `close()` before the main computation ends. A drain computation that still waits for records is a deadlock to the
reactor.
