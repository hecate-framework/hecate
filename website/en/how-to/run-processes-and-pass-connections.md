---
description: Run programs to completion or keep them running with hecate.reactor, talk to a child over a message pipe and hand it an open connection.
hecate: "0.x"
lua: "5.5"
order: 5
---

# Run child processes and pass connections between processes

This guide shows how to run another program from a hecate process, how to talk to it, and how to
give it an open TCP connection. These are the primitives on which multi-process serving is
built; read [Multi-process serving](../explanation/multi-process-serving.md) for the design. It is
written for hecate 0.x and Lua 5.5.

In hecate, to [spawn](../reference/glossary.md#concurrency) means to start an operating-system process. Starting a
[coroutine](../reference/glossary.md#concurrency) is a `fork`. The connection between a parent and
its child is a [message pipe](../reference/glossary.md#concurrency).

## Choose between `run_process` and `spawn`

| | `reactor.run_process(program, args)` | `reactor.spawn(program, args, options)` |
|---|---|---|
| Use it for | a program that runs to completion | a child that stays alive |
| Returns | when the child has ended: `{ code, signal, stdout, stderr }` | at once: a `Process` |
| Output | captured | inherited, or ignored |
| Cancellation | terminates the child | leaves the child running |
| Message pipe | no | optional |

Neither starts a shell. `args` lists the arguments without the program name, so there is no
quoting to get wrong.

## Run a program to completion

`reactor.run_process` suspends the coroutine until the child ends. It returns the exit code,
the terminating signal (0 if none) and everything the child wrote to standard output and
standard error. If the coroutine is cancelled, for example by a deadline, the child is
terminated.

<!-- example: packages/reactor/examples/hecate.reactor.run_process.lua -->
```lua
-- Runs a program to completion and captures its output. The program is the Lua
-- interpreter that runs this file (`arg[-1]`), so the example needs nothing
-- installed.
local reactor = require("hecate.reactor")

reactor.run(function()
  local result = reactor.run_process(arg[-1], { "-e", "io.write('hello'); os.exit(3)" })
  print(("%s, exit code %d"):format(result.stdout, result.code))
end)
-- Prints: hello, exit code 3
```

The example runs the Lua interpreter that runs the file, found in `arg[-1]`. In your own code you
name the program you want. If it cannot be started, `run_process` raises `IoError`.

## Keep a child running

`reactor.spawn(program, args?, options?)` starts the child and returns a `Process` at once. The
options are:

- `env`: variables added to the environment the child inherits.
- `cwd`: the working directory of the child.
- `ipc`: `true` opens a message pipe to the child.
- `stdout` and `stderr`: `"inherit"` (the default) or `"ignore"`.

The returned `Process` has:

- `pid`, the operating-system identifier;
- `wait()`, which suspends until the child exits and returns `{ code, signal }`. Several
  coroutines may wait. Cancelling a wait leaves the child running;
- `kill(signal?)`, which sends a signal, `"sigterm"` by default, and does not suspend;
- `is_running()`;
- `ipc`, the message pipe, when you asked for one.

```lua
local worker = reactor.spawn("my-program", { "--port", "8080" }, { stdout = "ignore" })
-- ... later
worker:kill()        -- SIGTERM; "sigkill" cannot be caught
local status = worker:wait()
```

You own the child. Wait for it or kill it, and close `process.ipc` when you are done. `kill` is a
signal, not the cancellation mechanism: cancelling the coroutine that waits does not stop the
child. `kill` does nothing for a child that has already exited and treats a child that vanished
meanwhile as a success. An invalid signal raises `IoError`.

A running child keeps the reactor alive, so waiting for it with nothing else pending is not a
deadlock. `reactor.run` returns when its main coroutine ends, whether or not a child still runs. Wait for
your children, or kill them, before the main coroutine ends.

> [!WARNING] Relative search paths
> A child started from another Lua process finds its modules through `package.path`. That path may
> hold relative entries, which stop working when you set `cwd`. Make them absolute, or pass them
> through `LUA_PATH_5_5` and `LUA_CPATH_5_5` in `env`, as the examples do.

## Talk to a child over a message pipe

Start the child with `ipc = true`. The parent reads and writes through `process.ipc`, a `Peer`.
The child reaches its end with `reactor.ipc.parent()`, which returns `nil` when the process was
not started with a message pipe. It returns the same peer on every call and does not suspend.

Both ends use the same methods:

- `peer:send(message, stream?)` suspends until the message is handed to the operating system.
- `peer:receive()` suspends and returns `message, stream?`. It returns `nil` when the other end
  has closed the pipe, which is how a child learns that its parent is gone.
- `peer:close()` is idempotent and never suspends. A peer is `<close>`-able.

A message is a string of at most 16 MiB. Pass `{ max_message = n }` to `reactor.Peer` or to
`reactor.ipc.parent` to lower the limit. Serialise structured data yourself, for example as JSON:
`reactor` has no dependency on a JSON library.

Only one coroutine may receive at a time. A cancelled `receive` keeps the peer open and loses
nothing. A cancelled `send` closes the peer, because the amount sent is unknown.

<!-- example: packages/reactor/examples/hecate.reactor.spawn.lua -->
```lua
-- A long-lived child with a message pipe. The child is a second Lua interpreter
-- that waits for one message, answers it in capitals and exits; the parent
-- sends, receives and waits for the exit. The child needs the same module paths
-- as this process, hence the two environment variables.
local reactor = require("hecate.reactor")

local CHILD = [[
local reactor = require('hecate.reactor')
reactor.run(function()
  local parent = reactor.ipc.parent()
  parent:send(parent:receive():upper())
end)
]]

reactor.run(function()
  local process = reactor.spawn(arg[-1], { "-e", CHILD }, {
    ipc = true,
    env = { LUA_PATH_5_5 = package.path, LUA_CPATH_5_5 = package.cpath },
  })
  local peer <close> = assert(process.ipc)
  peer:send("hello")
  local answer = peer:receive()
  local status = process:wait()
  print(("%s, exit code %d"):format(answer, status.code))
end)
-- Prints: HELLO, exit code 0
```

Messages that the child sent before it exited stay readable until you close `process.ipc`.

A process that the child starts in turn gets neither the pipe nor the environment variable that
announces it. Only the child started with `ipc = true` can talk to its parent.

### Errors

A malformed frame, or a stream that arrives without its announcement or against it, raises
`TransportError` with `EPROTO` and closes the peer. A pipe that ends in the middle of a frame
raises `EPIPE`. A closed peer raises `EBADF`, or `ECANCELED` for a coroutine that was waiting while
the peer closed.

The methods of [`Peer`](../reference/reactor/Peer.md) list every error.

## Hand a connection to a child

`peer:send(message, stream)` passes an open `TcpStream` together with a message. The child's
`receive` returns both. From then on only the child owns the connection: the sender's copy is
closed when the hand-over completes.

Only a `TcpStream` can be handed over, and it must be open. This is the mechanism by which a
primary hands accepted connections to its workers.

<!-- example: packages/reactor/examples/hecate.reactor.Peer.send.lua -->
```lua
-- Hands a connection to another process. The parent accepts a TCP connection
-- and passes it to the child with the message "serve"; the child writes on the
-- stream it received, and the connection is closed in the parent by the
-- hand-over. The parent waits for the child's acknowledgement before it goes
-- on, as a sender should (on Windows the receiver's copy of the socket depends
-- on the sender still being there).
local reactor = require("hecate.reactor")

local CHILD = [[
local reactor = require('hecate.reactor')
reactor.run(function()
  local parent = reactor.ipc.parent()
  local message, stream = parent:receive()
  stream:write('handled by the child after ' .. message .. '\n')
  stream:close()
  parent:send('done')
end)
]]

reactor.run(function()
  local listener <close> = reactor.listen_tcp("127.0.0.1", 0)
  local port = listener:local_address().port
  local client = reactor.fork(function()
    local stream <close> = reactor.connect_tcp("127.0.0.1", port)
    return stream:read()
  end)
  local process = reactor.spawn(arg[-1], { "-e", CHILD }, {
    ipc = true,
    env = { LUA_PATH_5_5 = package.path, LUA_CPATH_5_5 = package.cpath },
  })
  local peer <close> = assert(process.ipc)
  peer:send("serve", listener:accept()) -- the stream now belongs to the child
  peer:receive() -- the child's acknowledgement
  process:wait()
  print((reactor.join(client):gsub("\n$", "")))
end)
-- Prints: handled by the child after serve
```

The stream is closed in the sender once it is handed over: using it afterwards raises
`TransportError` with `EBADF`.

> [!WARNING] Windows
> The operating system duplicates the socket for the receiver, and the duplicate is valid only
> while the sender's socket is open. The sender closes it as soon as `send` returns, which can be
> before the receiver calls `receive`. Have the receiver acknowledge with a message, and do not exit
> the sender before the acknowledgement arrives.

## Share a port between processes

Several processes can listen on one port with the `reuseport` option of `reactor.listen_tcp` and
`net.listen`, and the kernel balances the connections. It needs a luv that exposes it for TCP, which
luv 1.53 does not (OQ-43): the call raises `TransportError` with `ENOTSUP`. Test first, and fall back
to one process that accepts and hands each connection over, as above.

```lua
if reactor.supports_reuseport() then
  -- Every worker does this.
  listener = reactor.listen_tcp("0.0.0.0", 8080, { reuseport = true })
else
  -- the primary accepts and passes each connection to a worker with
  -- peer:send(message, stream)
end
```

Where it is supported, it says nothing about balance: macOS accepts the flag and does not balance.
Supervision (readiness, restarts, shutdown) is yours to write for now. The design that will provide
it is in [Multi-process serving](../explanation/multi-process-serving.md).

## Platform differences

- **Windows:** `kill` supports `SIGTERM`, `SIGKILL`, `SIGINT` and `0` only. Any other signal
  fails with `ENOSYS`, and the first three end the process at once, with no chance to clean up.
- **Windows:** a child ended by `kill` reports `code` 1 and `signal` 0. Detect a crash or a kill
  by `code` there. `signal` is meaningful only on Unix.
- **Windows:** a program is looked up in the working directory first, then in `PATH`. A relative
  `program` therefore depends on `cwd`.
- **Windows:** a `.cmd` or `.bat` script cannot be started directly, and is not found without its
  extension. Run `cmd.exe` with `/c` and the script instead.
- **Windows:** `"inherit"` needs a valid standard output and error in your process. A service
  without them must pass `"ignore"`.
- **Windows:** environment variable names are case-insensitive in `env`.

## See also

- [Multi-process serving](../explanation/multi-process-serving.md)
- Reference: [`reactor.spawn`](../reference/reactor/functions/spawn.md),
  [`reactor.run_process`](../reference/reactor/functions/run_process.md),
  [`Process`](../reference/reactor/Process.md), [`Peer`](../reference/reactor/Peer.md),
  [`reactor.ipc`](../reference/reactor/ipc.md)
