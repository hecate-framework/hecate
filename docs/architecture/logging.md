# Logging (`hecate.log`)

Package: `log` (layer 1, Runtime). Status: specification of the implemented behaviour (alpha) and of the
intended contract; decisions in [ADR 0004](../adr/0004-academic-vocabulary.md) (vocabulary),
[ADR 0018](../adr/0018-error-signalling.md) (errors) and [ADR 0025](../adr/0025-ambient-context.md)
(ambient context, Accepted). Where a statement describes something that is not implemented, it says so.

## Scope and non-goals

`hecate.log` writes structured records, each with an RFC 5424 severity, a message, structured fields and a
context, to pluggable sinks. Its dependencies are `core`, `reactor` and `json` (the JSON lines rendering).

Non-goals: metrics and tracing (a later, OpenTelemetry-compatible package); log shipping to remote collectors
(a sink may do it, none is provided); log rotation (the `FileSink` appends to one file); the syslog wire format of
RFC 5424 section 6 (the package uses the severities of section 6.2.1 and the timestamp profile of section 6.2.3,
not the message framing); configuration by file (see "Configuration").

## Severities

The eight severities of RFC 5424, section 6.2.1, as the enumeration `log.Severity` (`hecate.core.enumeration`).
Declaration order is the order of the codes, most urgent first; the code of a severity is its ordinal minus one.

| Code | Name | Meaning (RFC 5424) |
|---|---|---|
| 0 | `emergency` | the system is unusable |
| 1 | `alert` | action must be taken immediately |
| 2 | `critical` | critical conditions |
| 3 | `error` | error conditions |
| 4 | `warning` | warning conditions |
| 5 | `notice` | normal but significant condition |
| 6 | `informational` | informational messages |
| 7 | `debug` | debug messages |

There is no alias (`info` does not exist). `log.severity_code(severity)` returns the code, 0 to 7.
`log.Severity` offers `values()`, `names()`, `contains(value)`, `find(name)` and `size()`.

A *severity* is the urgency of a record; a logger records the severities at least as urgent as its own
`severity` option, never "level" or "threshold" (glossary, OQ-60).

- The `severity` option of `Logger` (a `log.Severity` value or its name) is the least urgent severity recorded;
  default `informational`.
- `logger:set_severity(severity)` changes it; `logger:severity()` returns it (a `log.Severity` value).
- `logger:is_enabled(severity)` tells whether a record of that severity would be built; use it to skip costly
  arguments (known pitfall: string formatting cost when a severity is disabled).
- An unknown severity (a name that is not one of the eight, or a value that is neither) raises
  `hecate.core.ArgumentError` in the constructor, `set_severity`, `is_enabled` and `log`.

## Logger

```lua
local log = require("hecate.log")
local logger = log.Logger({ severity = "informational", sinks = { sink }, name = "app" })
logger:warning("slow query", { millis = 120 })
```

Methods:

| Method | Semantics |
|---|---|
| `logger:log(severity, message, fields?)` | Records `message` at `severity` (a value or a name) when it is enabled. |
| `logger:emergency` ... `logger:debug` `(message, fields?)` | One method per severity; the same as `log` with that severity. There is no format-string form: build the text before the call, guarded by `is_enabled` when it is costly. |
| `logger:with_context(fields)` | Returns a child logger (below). |
| `logger:add_sink(sink)` | Adds a sink; the children see it too. |
| `logger:failures()` | Number of failures counted by the logger and its children (see "Behaviour when a sink raises"). |

Checks and order of work for a call:

1. The severity is resolved (`ArgumentError` if unknown), then compared with the logger's: a call less urgent
   returns **before anything else**, without checking the message or building a record.
2. `message` must be a string and `fields` a table or `nil` (`hecate.core.ArgumentError` otherwise).
3. The context is built (see "Records"), the clock is read, the record is built, and each sink receives it
   synchronously, in the order the sinks were added.

A logger holds the sink list and the failure count in state shared with its children, and keeps its severity,
name, clock, provider, `redact` set and context in its own state.

### Child loggers

`logger:with_context(fields)` returns a new logger whose context is the parent's extended with `fields` (the new
fields win). The child shares the sinks (including those added later) and the failure count of the parent, and
copies its name, clock, `context_provider` and `redact` names. **Its severity is a copy taken when it is created:**
a later `set_severity` on the parent does not change the child, and conversely. A child's context is fixed: it is
the way to carry request-scoped fields into code that receives the logger as an argument. `fields` that is not a
table raises `hecate.core.ArgumentError`.

### Fields and message shape

`message` is a human-readable, constant-as-possible text without interpolated data; the data goes in `fields`, a
table of keys to values (strings, numbers, booleans, nested tables). Fields are not validated. When the logger has
no `redact` option the record holds the **caller's own table** (it is not copied): do not mutate it after the call,
especially when a sink defers the write (`AsyncSink`). With `redact`, the record holds a redacted copy.

### Error values and how errors are logged

The logger has no special handling of error values: `message` must be a string. To log a failure, put the text in
the message and the stable data in fields, for example
`logger:error("request failed", { code = err.code, reason = tostring(err) })`.
A table placed in a field is rendered as `{...}` by the `ConsoleSink`; the `JsonLinesSink` hands it to
`hecate.json`, and if that cannot encode the record it keeps the record with the message only and an
`encoding_error` member (see "Sinks"). Automatic serialisation of `hecate.core.Error` values (code, context, cause
chain) is **not provided**; it is not decided (see "Open points").

Errors raised by the package itself are in "Error codes".

## Records

`log.Record` is what sinks receive. A sink reads it and never modifies it.

| Field | Type | Content |
|---|---|---|
| `severity` | `log.Severity` value | the severity of the call |
| `message` | string | the message |
| `fields` | table | the fields of the call (`{}` when none) |
| `context` | table | the context, merged (below); `{}` when empty |
| `timestamp` | number | the reading of the clock, in seconds since the epoch (may be fractional) |
| `logger` | string or `nil` | the `name` option of the logger |

The RFC 5424 code is not stored: `log.severity_code(record.severity)` computes it, and the JSON lines rendering
writes it as `code`.

### Context

The context of a record is built at each call, in this order, later entries winning:

1. the ambient context, supplied by the `context_provider` of the logger (default: the fields bound by `log.bind`);
2. the context of the logger (`context` option, then each `with_context` of its ancestry).

So a logger's own context wins over the ambient one. The fields of the call are kept apart, in `fields`.
The record's `context` is always a fresh table.

### Timestamps and clock

`timestamp` is read once per record from the `clock` option, a function that returns seconds since the epoch;
the default is `os.time` (whole seconds). Pass a function that returns a fractional value for sub-second
precision, or a fixed function in tests. The renderings use UTC and the RFC 3339 profile of RFC 5424,
section 6.2.3 (`2026-10-26T12:00:00Z`; the JSON lines sink adds `.mmm` milliseconds when the value is fractional,
the console sink never does). A clock that raises is **not** caught: the error reaches the caller.

The logger does not read the reactor's clock. Under a virtual clock (`reactor.Reactor({ clock = "virtual" })`)
the default `os.time` still returns real time; a test that needs deterministic timestamps passes its own `clock`.
`LimitedSink` has its own `clock` option for the same reason.

## Sinks

### The sink interface

A sink is any object with a synchronous method `write(record)` that **does not suspend**. It is checked by
`Logger` and the decorators (a table with a `write` function, `hecate.core.ArgumentError` otherwise); there is no
base class. Optionally a sink has `close()`, which `AsyncSink` calls on its target. Annotated as `hecate.log.Sink`.

A logger given `sinks` in its options, or `add_sink`, writes each record to every sink in registration order. A
decorator (`LimitedSink`, `AsyncSink`) takes its target in `options.sink`.

### Provided sinks

| Sink | Behaviour |
|---|---|
| `MemorySink({ capacity? })` | Keeps records: `records()` (a copy, oldest first), `clear()`, `dropped()`. With `capacity` (a positive integer) the oldest records are dropped beyond it and counted; default unbounded. For tests and inspection. Keeps `Secret` values as they are. |
| `ConsoleSink({ output })` | Calls `output(line)` with `timestamp SEVERITY [logger] message key=value ...` and a final newline. Timestamp in UTC to the second; severity upper case; the `[logger]` part is omitted without a name; context pairs then field pairs, each sorted by key; values with spaces, `=`, `"` or empty are quoted; a table renders `{...}`; a secret renders `[redacted]`; control characters are escaped (`\xNN`) in values and keys and replaced by a space in the message; a value over 200 characters is cut with `...`. |
| `JsonLinesSink({ output })` | Calls `output(line)` with one JSON object and a final newline: `timestamp` (RFC 3339, UTC), `severity` (name), `code` (0 to 7), `message`, `logger`, `context`, `fields` (the last three omitted when empty). A `Secret` becomes `"[redacted]"` at any depth; nesting beyond 16 levels becomes `"[truncated]"` (it also stops cycles). If `hecate.json` cannot encode the record, the line keeps the base members and an `encoding_error`, with `context` and `fields` omitted, and bytes of a message that is not valid UTF-8 escaped as `\xNN`. |
| `FileSink({ path })` | Appends JSON lines (the rendering of `JsonLinesSink`) to `path`, created when missing. Synchronous: each write blocks the running computation for its duration; the descriptor is line-buffered, so each record is handed to the operating system at the end of its line (no `fsync`). A failed open raises `hecate.core.Error`; a failed write raises `hecate.core.Error` from `write`. `close()` flushes and closes; later writes are ignored. |
| `LimitedSink({ sink, exempt?, sample?, rate?, burst?, random?, clock? })` | Decorator. Records at least as urgent as `exempt` (default `warning`) always pass; the others are sampled (`sample`, a fraction in (0, 1], default 1, using `random`, default `math.random`), then limited by a token bucket (`rate` records per second, `burst` capacity, default `max(rate, 1)`, `clock` default `os.time`). Dropped records are counted in `dropped()`. It has no `close`: a decorator stack that ends in a `FileSink` must close the file itself. |
| `AsyncSink({ sink, capacity? })` | Decorator that moves the write off the caller (below). |

`ConsoleSink` and `JsonLinesSink` call `output`; it is synchronous and must not suspend (a suspension inside a
synchronous `write` is outside the contract). The `JsonLinesSink` needs the native module of `hecate.json`;
when it is missing every write raises and a `Logger` counts it.

### Ordering and flushing guarantees

- A logger delivers each record to its sinks before the call returns, in the order of the calls and, for one
  record, in the order of the sinks. Computations interleave only at suspension points, and a logger call has
  none, so the records of one logger reach a synchronous sink in call order.
- `AsyncSink` preserves the order of its queue (first in, first out) and writes to its target one record at a
  time; `flush()` returns once every record queued before the call has been written (written means that
  `target:write` returned or raised).
- No sink calls `fsync`; the `FileSink` guarantees only the line buffering above. `flush` of an `AsyncSink` does
  not flush the target beyond what the target's `write` does.
- Nothing is flushed at process exit by itself: call `close()` (see "What happens on close").

### `AsyncSink`

```lua
local async = log.AsyncSink({ sink = log.FileSink({ path = "app.log" }), capacity = 1024 })
```

- `write(record)` never suspends. It appends the record to a bounded queue and adds one unit to a
  `reactor.Semaphore` (Dijkstra's V); a **drain computation**, started with `reactor.detach` at the **first**
  `write`, takes a unit (P) and writes to the target.
- The first `write` therefore must run inside a reactor. Outside one `detach` raises
  `hecate.core.NonYieldableContextError`; a `Logger` counts it in `failures()` and the record is lost.
- Back-pressure is loss, never waiting: when `capacity` records (default 1024; a positive integer) are waiting, the
  new record is dropped and counted in `dropped()`. `pending()` is the number of records waiting. The markers of
  `flush` and `close` are not records and do not count against the capacity.
- A target that raises is counted in `failures()` of the `AsyncSink`; the record is lost and the drain goes on.
  The failure is **not** reported to the `Logger`, whose `failures()` does not see it.
- A slow target delays no caller; its cost is queue growth up to `capacity`, then drops.
- `flush()` and `close()` suspend (`---@async`). `flush()` does nothing on a sink never written to or already
  closed.
- The drain computation lives in the application scope (`detach`): it is not cancelled when the scope of the
  request that wrote first ends.

### What happens on close

`AsyncSink:close()`: marks the sink closed (later writes are ignored, silently), queues a stop marker, waits until
every record queued before it has been written, waits for the drain computation to end, then calls `close()` on the
target if it has one. A second call does nothing. A `close` of the target that raises propagates to the caller of
`AsyncSink:close()`. A sink never written to has no drain computation: `close` only closes the target.
Call `close()` before the main computation ends: a drain computation still waiting for records is a deadlock to the
reactor (`reactor.run: deadlock`). `FileSink:close()` is synchronous and idempotent. `MemorySink`, `ConsoleSink`,
`JsonLinesSink` and `LimitedSink` have no `close`. The `Logger` has no `close`: it owns no resource, closing is
the job of whoever created the sink.

### Behaviour when a sink raises

A sink must never fail the caller. The `Logger` calls each `write` under `pcall`; a sink that raises is counted in
`logger:failures()` (shared with the children), the error is discarded, and the following sinks still receive the
record. The count is the only trace: a logger does not log its own failures (that could recurse); watch
`failures()` or give the application a sink of last resort. The same counter counts a `context_provider` that
raises or returns something that is neither a table nor `nil`; the record is then written without the ambient
context.

Not caught, because they are programmer errors or outside the sink: an invalid severity, message or fields
(`hecate.core.ArgumentError`), a `clock` that raises.

## Ambient context

The concept is the **ambient context** of [ADR 0025](../adr/0025-ambient-context.md): immutable key-value bindings
visible in a computation and in the computations it forks or detaches. The package summary keeps the words
"per-scope context" (owner decision, phase-0 coherence review, Resolution F02); both name the same thing here.

- `reactor.with_ambient(key, value, fn, ...)` binds `key` for the duration of `fn`; `reactor.ambient(key)` reads it.
  `fork`, `detach` and `Scope:fork` give the child the bindings visible at the moment of the call
  ([concurrency.md](concurrency.md), "Ambient context").
- `log.bind(fields, fn, ...)` binds the table `fields` under a key private to `hecate.log`, merged over the
  fields bound outside (the inner `fields` win), runs `fn(...)` and returns its results. It raises
  `hecate.core.ArgumentError` if `fields` is not a table and `hecate.core.NonYieldableContextError` outside a
  managed coroutine (it is `with_ambient`). It does not suspend by itself; `fn` may.
- The default `context_provider` reads those fields (`nil` outside a reactor, without counting a failure). A
  logger created with its own `context_provider` ignores `log.bind`: the provider is the single source of the
  ambient context of that logger.
- Inheritance: a record logged by a computation forked or detached inside `log.bind` carries the fields; a
  record logged after `fn` returned, or by a computation created before the binding, does not. Bindings made by a
  child are invisible to its parent and siblings.
- Precedence: logger context over the ambient context. The fields of a call are separate from both.
- `kernel` binds the request id around each request with `log.bind` (roadmap, not implemented yet).
- `Logger:with_context` and `log.bind` are complementary: `with_context` is explicit and travels with the logger
  value; `log.bind` is implicit and travels with the computation. Use the second for request-scoped values, and
  the first for fields that belong to a component.

## Configuration

Today a logger is configured in code only. Options of `Logger`:

| Option | Default | Meaning |
|---|---|---|
| `severity` | `informational` | least urgent severity recorded (value or name) |
| `sinks` | none | list of sinks; a logger without sink records nothing anywhere |
| `name` | none | stored in every record as `logger` |
| `context` | `{}` | fields added to every record |
| `context_provider` | the fields bound by `log.bind` | function returning the ambient context or `nil` |
| `redact` | none | list of field names, case-insensitive, any depth up to 16 levels, in fields and context; their values are wrapped in a `Secret` |
| `clock` | `os.time` | function returning seconds since the epoch |

Options of the sinks are in "Provided sinks". Option checks raise `hecate.core.ArgumentError`.

`hecate.config` is not implemented and defines no key for logging yet. Keys for the severity, the sinks and
the named severities per logger are **to be specified with `config`** (future); nothing in this document commits
to their names.

## Secrets and privacy

- `log.Secret(value)` marks a value: `tostring` returns `[redacted]`, `reveal()` returns the value. The
  `ConsoleSink` and `JsonLinesSink` (hence `FileSink`) never render a secret, at any depth of a record up to 16
  levels. This is the invariant "secrets marked as such are never rendered".
- The `redact` option wraps by field name before any sink sees the record: it is the only redaction hook provided
  and it works on plain tables (tables with a metatable, such as class instances, are not walked; beyond 16 levels
  the value is left as is).
- `MemorySink` and custom sinks receive the `Secret` object itself (not its value); a custom sink must render
  it with `tostring` or the `REDACTED` text, never `reveal()`.
- **Not provided:** redaction by value pattern (card numbers, tokens in free text), redaction of the `message`,
  custom redaction functions, and automatic scrubbing of values inside a table that is not walked. Never put a
  secret in the message.
- A control character in a value cannot forge a line in the console rendering (escaped); the JSON rendering
  escapes by construction.
- Records can hold personal data in `fields` and `context`; retention and access are the application's concern
  (the `FileSink` writes with the process's default permissions).

## Error codes and messages

`hecate.log` defines no error class of its own. It raises:

| Class (stable `code`) | When |
|---|---|
| `hecate.core.ArgumentError` | unknown severity; message not a string; fields not a table; sink without `write`; invalid `redact`, `capacity`, `sample`, `rate`, `burst`, `output`, `path` |
| `hecate.core.Error` | `FileSink` cannot open or write its file |
| `hecate.core.NonYieldableContextError` | `log.bind`, or the first write of an `AsyncSink`, outside a managed coroutine |

Messages follow [coding-standards.md](coding-standards.md#errors): lower case first word, the offending value and
the expected one, and the qualified prefix, for example `log.Logger: invalid redact option: expected a list of
field names`, `log.Logger.with_context: expects a table, got string`, `log.AsyncSink: invalid capacity: expected a
positive integer`, `log.FileSink: cannot open log file: ...`. The prefix names the call the caller wrote, including the
convenience methods (`log.Logger.informational: message must be a string, got number`) and the severity checks
(`log.Logger.set_severity: invalid severity ...`).

## Concurrency and suspension

- Logging never suspends the caller on the hot path (invariant): `Logger` methods, `log.bind`'s own work,
  `with_context`, `add_sink`, and the `write` of every provided sink do not suspend and do not touch the
  reactor, except `AsyncSink`, which starts its drain computation once, and only queues afterwards.
- Everything that may suspend is annotated `---@async`: `AsyncSink:flush()` and `AsyncSink:close()`, and nothing
  else of the package. The suspension check of testing.md
  (`packages/reactor/tests/unit/suspension_test.lua`) covers `hecate.reactor`; a counterpart for this package
  is not written yet.
- A `Logger` can be used outside a reactor, for a script or a test, with every sink except `AsyncSink`.
- Sinks hold mutable state without locks; this is safe because computations interleave only at suspension
  points and no `write` of a provided sink has one. A custom sink whose `write` suspended would break the order
  guarantees and the invariant.
- A `FileSink` write is blocking I/O (`io`) on the reactor's thread, line-buffered. Wrapping it in an `AsyncSink`
  moves the write out of the caller's path but not off the thread: the drain computation's write still blocks the
  reactor while it runs (a non-blocking file sink is not provided).

## Testing guidance

- Use `MemorySink` and a fixed `clock`; assert on `records()`.
- Context propagation: run under `reactor.Reactor({ clock = "virtual" })`, bind with `log.bind`, log from
  `fork`ed and `detach`ed computations after a `reactor.sleep`, and assert on `record.context`.
- Back-pressure: an `AsyncSink` with a small `capacity` and a target that sleeps; assert `dropped()`, `pending()`
  and, after `flush()`, order. Always `close()` before the reactor returns.
- A failing sink: `{ write = function() error("x") end }` plus `failures()`.
- Secrets: render through `JsonLinesSink` and `ConsoleSink` and search the output for the secret value.
- Every example in `packages/log/examples/` is run by a test; the how-to page embeds them.

## Open points

- [OQ-63](../open-questions.md): two error messages do not carry a qualified prefix.
- Keys of `hecate.config` for logging: with the `config` package (roadmap, Phase 2).
