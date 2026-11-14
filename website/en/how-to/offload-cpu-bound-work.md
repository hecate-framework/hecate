---
description: Run CPU-bound Lua functions on the libuv thread pool with reactor.offload, so the reactor keeps serving other computations.
hecate: "0.x"
lua: "5.5"
order: 15
---

# Offload CPU-bound work to the thread pool

The [reactor](../reference/glossary.md#concurrency) runs every computation on one thread. A computation that calculates
for a long time without [suspending](../reference/glossary.md#concurrency) stops every other computation until it ends.
Hashing a password, compressing a file and parsing a large document are such work.

`reactor.offload(fn, ...)` runs such a function on libuv's thread pool instead. It suspends only the caller, so the
reactor keeps serving the other computations.

This guide is written for hecate 0.x and Lua 5.5. Call `offload` inside `reactor.run`, like every call that suspends.
It needs the real clock: on a reactor with the virtual clock it raises `hecate.core.Error`.

## Run a function on the pool

`offload` takes the function and its arguments. It returns the results of the function.

The example counts the primes below 200000 on the pool. Meanwhile, a ticker computation shows that the reactor stays
free:

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

### What the function sees

The function runs in the separate Lua state of a pool thread, with a fresh environment for each call. It sees the
standard libraries and `require`. It sees nothing of the reactor thread: no global of yours, no loaded module, no
reactor.

The function must not call anything that suspends.

A global that the function assigns disappears with the call. Do not change the standard library tables, which every
later call on that thread shares.

## Write a self-contained function

The function travels to the pool thread as bytecode. The local variables it captures from the surrounding code, its
upvalues, do not travel with it.

So `offload` refuses a function that captures anything other than the global environment. It raises an
`ArgumentError` that names the variable:

```lua
local rounds = 10
-- ArgumentError: captures the local variable rounds
reactor.offload(function() return rounds end)
-- correct: the value is an argument
reactor.offload(function(n) return n end, rounds)
```

`offload` also refuses a C function, and a function compiled without debug information, whose upvalues it cannot
check.

### Use a module on the pool thread

To use a module on the pool thread, `require` it inside the function. The pool thread searches the paths of the
`LUA_PATH` and `LUA_CPATH` environment variables. It does not see a `package.path` that your program changed while
running.

## Know what crosses

Arguments and results are copied from one Lua state to the other. Two kinds of value can cross:

- `nil`, booleans, numbers and strings. An integer stays an integer, and a float stays a float. A string can have any
  length and any bytes;
- plain tables built from them. A plain table has no metatable and keys that are booleans, numbers or strings. It does
  not contain itself, and it is nested at most 100 levels deep.

A table reached twice is copied twice, so the copies are distinct tables. `nil` values keep their place. There is no
limit on the number of arguments or results.

### What cannot cross

A function, a coroutine, a userdata, or a table with a metatable cannot cross. An instance of a class is such a table.

- As an argument, it raises `ArgumentError` before anything runs.
- As a result, it raises `reactor.OffloadError`.

## Handle errors

An error raised by the function reaches the caller as a `reactor.OffloadError`. Its `err.context.reason` is `"raised"`.

- The message starts with `reactor.offload:`, followed by the original message. For an error object, the original
  message is its `message` field.
- `err.context.traceback` holds the traceback on the pool thread.
- `err.context.code` keeps the code of a hecate error.

The original error object stays on the pool thread.

```lua
-- In app.lua, line 12:
local ok, err = pcall(reactor.offload, function() error("corrupt input") end)
-- err.message: "reactor.offload: app.lua:12: corrupt input"
```

Two other reasons exist:

- `"result"`: a result cannot be copied;
- `"pool_thread"`: the pool thread itself failed. The function cannot be loaded there, or the arguments cannot be
  decoded.

When libuv refuses the work, `offload` raises `hecate.reactor.IoError`.

## Bound the work, not only the wait

A function that waits in the queue is never started if its caller is
[cancelled](../reference/glossary.md#concurrency). A deadline set by `reactor.deadline`, or the
[scope](../reference/glossary.md#concurrency) of the caller, can cancel it. The next section describes the queue.

A function that already runs on the pool cannot be interrupted. Its caller is released at once, and the result is
discarded when it arrives. But the pool thread stays busy until the function returns, and `reactor.run` does not
return before it does.

So give long work its own limit, for example a maximum input size or a number of rounds.

## Size the pool

The pool has 4 threads by default. It is shared with the file system and with name resolution.

So that offloaded work never takes every thread, at most 3 functions run on the pool at once. That is the pool size
minus one, and at least 1. Further calls wait in a queue and start in arrival order.

Change the limit with the `max_offloads` option of the reactor:

```lua
reactor.Reactor({ max_offloads = 2 }):run(main)
```

The size of the pool is fixed when it is first used, and its threads never exit. A program that offloads a lot sets the
environment variable `UV_THREADPOOL_SIZE`, from 1 to 1024, before it starts. The default limit follows it.

## Decide what to offload

Each call has a cost. It copies its arguments and results, and it loads the function on the pool thread. A round trip
costs tens of microseconds. Copying a large table costs time on the reactor thread, in proportion to its size.

So offload work of a millisecond or more. Keep short functions on the reactor thread.

### Release memory

What the function allocates stays in the Lua state of the pool thread after it returns, until that thread runs Lua
again. A program can hold up to the pool size times the peak allocation of one call.

A function that builds large data drops it before returning. It clears its references to that data, then calls
`collectgarbage()`.
