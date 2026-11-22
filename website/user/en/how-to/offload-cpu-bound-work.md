---
description: Run CPU-bound Lua functions on the libuv thread pool with reactor.offload, so the reactor keeps serving other computations.
hecate: "0.x"
lua: "5.5"
order: 15
---

# Offload CPU-bound work to the thread pool

This guide shows how to run a long calculation off the reactor thread with `reactor.offload`. It is written for
hecate 0.x and Lua 5.5.

The [reactor](../reference/glossary.md#concurrency), the event demultiplexer of `hecate.reactor`, runs every
computation on one thread. A computation that calculates for a long time without
[suspending](../reference/glossary.md#concurrency), that is without yielding to the reactor, stops every other
computation until it ends. Hashing a password, compressing a file and parsing a large document are such
calculations.

`reactor.offload(fn, ...)` runs such a function on libuv's thread pool instead, and suspends only the caller. Call it
inside `reactor.run`, like every call that suspends.

## Run a function on the pool

`offload` takes the function and its arguments, and returns the function's results:

<!-- example: packages/reactor/examples/hecate.reactor.offload.lua -->
```lua
-- A CPU-bound function runs on the libuv thread pool while the reactor
-- keeps serving other computations. The function is self-contained: what
-- it needs arrives as arguments, and its results are copied back.
local reactor = require("hecate.reactor")

reactor.run(function()
  local ticks = 0
  local ticker = reactor.fork(function()
    while true do
      reactor.sleep(0.001)
      -- Counted after a completed sleep: the reactor was free meanwhile.
      ticks = ticks + 1
    end
  end)
  local count, largest = reactor.offload(function(limit)
    -- The primes below `limit`, by trial division: deliberately slow work.
    local primes = {}
    for n = 2, limit do
      local prime = true
      for d = 2, math.floor(math.sqrt(n)) do
        if n % d == 0 then prime = false; break end
      end
      if prime then primes[#primes + 1] = n end
    end
    return #primes, primes[#primes]
  end, 200000)
  ticker:cancel()
  print(("%d primes, the largest is %d, the reactor ticked: %s"):format(count, largest, tostring(ticks > 0)))
end)
-- Prints: 17984 primes, the largest is 199999, the reactor ticked: true
```

While the primes are computed, the ticker keeps running on the reactor thread.

The function runs in the separate Lua state of a pool thread, with a fresh environment for each call. It sees the
standard libraries and `require`. It sees nothing of the reactor thread: no global of yours, no loaded module, no
reactor.

Three rules follow:

- the function must not call anything that suspends;
- a global it assigns disappears with the call;
- it must not change the standard library tables, which every later call on that thread shares.

## Write a self-contained function

The function travels to the pool thread as bytecode. The local variables it captures from the surrounding code (its
upvalues) do not travel with it.

`offload` therefore refuses a function that captures anything other than the global environment. It raises an
`ArgumentError` that names the variable. Pass the value as an argument instead:

```lua
local core = require("hecate.core")
local reactor = require("hecate.reactor")

reactor.run(function()
  local rounds = 10
  local ok, err = pcall(reactor.offload, function() return rounds end)
  print(ok, core.name(err))
  -- Prints: false	ArgumentError
  print(reactor.offload(function(n) return n * 2 end, rounds))
  -- Prints: 20
end)
```

To use a module on the pool thread, `require` it inside the function. The pool thread searches the paths of the
`LUA_PATH` and `LUA_CPATH` environment variables. It does not see a `package.path` your program changed while
running.

## Know what crosses

Arguments and results are copied from one Lua state to the other. These values can cross:

- `nil`, booleans and strings, of any length and with any bytes;
- numbers: an integer stays an integer, and a float stays a float;
- plain tables built from them. A plain table has no metatable, its keys are booleans, numbers or strings, it does
  not contain itself, and it has at most 100 levels of nesting.

```lua
local reactor = require("hecate.reactor")

reactor.run(function()
  local copy = reactor.offload(function(t) return t end, { 1, { 2.0 }, "x" })
  print(math.type(copy[1]), math.type(copy[2][1]), copy[3])
  -- Prints: integer	float	x
  print(reactor.offload(function(...) return select("#", ...) end, 1, nil, 3))
  -- Prints: 3
end)
```

There is no limit on the number of arguments or results, and `nil` values keep their place, as the second call
shows.

A table reached twice is copied twice, so the copies are distinct tables.

Some values cannot cross: a function, a coroutine, a userdata, or a table with a metatable (an instance of a class,
for example).

- As an argument, such a value raises `ArgumentError` before anything runs.
- As a result, it raises `reactor.OffloadError`.

## Handle errors

An error raised by the function reaches the caller as a `reactor.OffloadError`, with `err.context.reason` set to
`"raised"`:

```lua
local core = require("hecate.core")
local reactor = require("hecate.reactor")

reactor.run(function()
  local ok, err = pcall(reactor.offload, function()
    error("corrupt input", 0)
  end)
  print(core.name(err), err.context.reason)
  -- Prints: OffloadError	raised
  print(err.message)
  -- Prints: reactor.offload: corrupt input
end)
```

The message starts with `reactor.offload:`, followed by the original message. For an error object, that is its
`message` field. A string raised with a position keeps it: `reactor.offload: app.lua:12: corrupt input`.

The context carries two more fields:

- `err.context.traceback` holds the traceback on the pool thread;
- `err.context.code` keeps the code of a hecate error.

The original error object stays on the pool thread.

Two other reasons exist:

- `"result"`: a result cannot be copied;
- `"pool_thread"`: the pool thread itself failed. The function cannot be loaded there, or the arguments cannot be
  decoded.

## Bound the work, not only the wait

A function waiting in the queue (see below) is never started if its caller is
[cancelled](../reference/glossary.md#concurrency), by `reactor.deadline` or by its
[scope](../reference/glossary.md#concurrency), the region that owns the computations forked in it.

A function that already runs on the pool cannot be interrupted:

- its caller is released at once, and the result is discarded when it arrives;
- the pool thread stays busy until the function returns;
- `reactor.run` does not return before the function does.

Give long work its own limit, for example a maximum input size or a number of rounds.

## Size the pool

The pool has 4 threads by default. It is shared with the file system and name resolution.

So that offloaded work never takes every thread, at most 3 functions run on the pool at once: the pool size minus
one. Further calls wait in a queue and start in arrival order. Change the limit with the `max_offloads` option of the
reactor:

```lua
reactor.Reactor({ max_offloads = 2 }):run(main)
```

The pool's size is fixed when it is first used, and its threads never exit. A program that offloads a lot sets the
environment variable `UV_THREADPOOL_SIZE` (from 1 to 1024) before it starts. The default limit follows it.

### Offload long work only

Each call copies its arguments and results, and loads the function on the pool thread. A round trip costs tens of
microseconds. Copying a large table costs time on the reactor thread, in proportion to its size.

Offload work of a millisecond or more, and keep short functions on the reactor thread.

### Release memory on the pool thread

What the function allocates stays in the pool thread's Lua state after it returns, until that thread runs Lua again.
A program can hold up to the pool size times the peak allocation of one call.

A function that builds large data drops it before returning: it clears its references to that data, then calls
`collectgarbage()`.

## See also

- [Concurrency](concurrency.md): deadlines, scopes and cancellation.
- [The concurrency model](../explanation/concurrency-model.md): why one reactor, and processes for several cores.
- Reference: [`hecate.reactor`](../reference/reactor/index.md)
