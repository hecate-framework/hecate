---
description: Start child processes, exchange messages with them over a message pipe, hand them accepted connections and share a listening port.
hecate: "0.x"
lua: "5.5"
---

# Run child processes and pass connections between processes

This guide shows how to start a long-lived child process, talk to it, hand it a
connection, and let several processes listen on one port. It was written for hecate 0.x
and Lua 5.5, and it covers the primitives of `hecate.reactor`. The supervision of
[workers](../reference/glossary.md#concurrency) and the choice of
[listening strategy](../reference/glossary.md#concurrency) belong to the `kernel` package
([ADR 0023](https://github.com/hecate-framework/hecate/blob/main/docs/adr/0023-multi-process-serving.md)).

Workers share nothing. They have their own Lua state and their own
[reactor](../reference/glossary.md#concurrency), and they exchange only strings and
connections.

::: note Vocabulary
To *spawn* is to start an operating-system process. A
[coroutine](../reference/glossary.md#concurrency) is started with `fork`. A *message pipe*
is the framed connection between a process and its child, and it is not a *channel*,
which connects coroutines of one process.
:::

## Run a program to completion

`reactor.run_process(program, args)` suspends until the program ends. It returns
`{ code, signal, stdout, stderr }`. Cancelling the caller terminates the child.

```lua
local result = reactor.run_process("lua", { "-e", "io.write('hi')" })
print(result.code, result.stdout) -- 0   hi
```

Use `reactor.spawn` when the child must outlive the call.

## Start a long-lived child

`reactor.spawn(program, args?, options?)` returns a `Process` at once. The child keeps
running while you do other work.

```lua
local child = reactor.spawn("lua", { "worker.lua" }, {
  ipc = true,
  env = { WORKER_ID = "1" },
  stdout = "inherit",
})
print(child.pid, child:is_running())
local status = child:wait() -- suspends; { code, signal }
```

| Option | Meaning |
|---|---|
| `env` | Variables added to the inherited environment. Names are case-insensitive on Windows. |
| `cwd` | Working directory of the child. |
| `ipc` | `true` opens a message pipe to the child, as `child.ipc`. |
| `stdout`, `stderr` | `"inherit"` (default) or `"ignore"`. |

You are responsible for the child. Call `child:wait()` or `child:kill(signal?)`, and close
`child.ipc`. A running child does not keep `reactor.run` from returning when the main
coroutine ends, so wait for it when you need its result.

`kill` is not cancellation. It sends a signal, and it treats an already finished child as
success. Cancelling the coroutine that waits for a child, with a
[scope](../reference/glossary.md#concurrency) or a deadline, leaves the child running.
Stop it yourself.

::: warning Windows
Only `SIGTERM`, `SIGKILL`, `SIGINT` and `0` work with `kill`. A killed child reports
`code` 1 and `signal` 0. A `.cmd` or `.bat` script cannot be started directly: run
`cmd.exe` with `/c`. If this process has no valid standard output and error, such as a
service, use `"ignore"`.
:::

## Talk to the child over a message pipe

With `ipc = true`, the parent holds `child.ipc`, a `Peer`. The child gets its end with
`reactor.ipc.parent()`, which returns `nil` when the child was started without `ipc`.

Parent:

```lua
local peer = child.ipc
peer:send("hello")          -- suspends; a string up to max_message bytes
print(peer:receive())       -- HELLO
peer:close()                -- the child sees the end and can exit
child:wait()
```

Child (`worker.lua`):

```lua
local reactor = require("hecate.reactor")

reactor.run(function()
  local peer = assert(reactor.ipc.parent(), "not started with ipc")
  while true do
    local message = peer:receive()
    if message == nil then return end -- the parent closed its end
    peer:send(message:upper())
  end
end)
```

Messages are strings. Serialise structured data yourself, for example as JSON, because
`reactor` sits below the JSON package.

- `peer:receive()` returns `nil` when the other end closed.
- A message is limited to 16 MiB by default. Set `{ max_message = n }` in
  `reactor.Peer(handle, options)` or `reactor.ipc.parent(options)`.
- Cancelling a `receive` keeps the peer open and loses nothing.
- A malformed frame raises `TransportError` with `errno` `EPROTO` and closes the peer.
  A pipe that ends in the middle of a frame raises `EPIPE`. A closed peer raises `EBADF`.

The child does not pass the message pipe on. A process the child starts in turn gets
neither the pipe nor the environment marker that announces it.

## Hand an accepted connection to a child

`peer:send(message, stream)` passes a `TcpStream` with a message. The stream is closed in
the sender afterwards. The receiver gets it as the second result of `receive`.

Parent (the primary):

```lua
local stream = listener:accept()
peer:send("job-1", stream) -- `stream` is closed here once handed over
```

Child (a worker):

```lua
local message, stream = peer:receive()
if stream then
  local connection <close> = stream
  connection:write("handled " .. message)
end
```

This is how a primary can accept all connections and distribute them to workers: it is
the `round_robin` strategy, which works on every platform. A connection stays on the
worker that received it.

A stream that arrives without its announcement, or the reverse, raises `TransportError`
`EPROTO` and closes the peer.

::: warning Windows
The receiver gets a duplicate of the stream. It is valid only while the sender's socket
is open, and the sender closes it when `send` returns. Have the receiver acknowledge with
a message before the sender exits.
:::

## Let several processes listen on one port

With `reuseport`, each process binds its own socket to the same address and port, and the
kernel spreads the new connections between them. The primary is not in the data path.

```lua
if reactor.supports_reuseport() then
  local listener <close> = reactor.tcp_listen("0.0.0.0", 8080, { reuseport = true })
  -- or net.listen("0.0.0.0", 8080, { reuseport = true })
end
```

Keep in mind:

- `reactor.supports_reuseport()` probes once and caches the answer. Without support,
  asking for `reuseport` raises `TransportError` with `errno` `ENOTSUP`. The option is
  never ignored.
- Every listener on the port must use `reuseport`. A listener without it, or one of the
  other kind, is refused with `EADDRINUSE`.
- The flag does not promise balance. macOS accepts it and does not balance, so use
  connection passing there.
- It needs a luv with TCP `reuseport`. Until one is available, the listening strategy
  `auto` of ADR 0023 chooses `round_robin` on Linux too (open question OQ-43).

## Stop a child in an orderly way

1. Send a message that asks the child to stop, or close `child.ipc`.
2. Wait for the child with a [deadline](net-deadlines.md).
3. Kill it if the deadline expires.

```lua
local ok = pcall(reactor.deadline, 5, function() return child:wait() end)
if not ok then
  child:kill()
  child:wait()
end
```

A child that sees its pipe close (because the parent died) should drain and exit, which
protects against orphans on every platform.

## See also

- [Send datagrams and use local pipes](net-udp-and-pipes.md)
- [ADR 0023: multi-process serving](https://github.com/hecate-framework/hecate/blob/main/docs/adr/0023-multi-process-serving.md)
