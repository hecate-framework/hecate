---
description: Run CPU-bound Lua functions on the libuv thread pool with reactor.offload, so the reactor keeps serving other computations.
hecate: "0.x"
lua: "5.5"
order: 15
---

# Offload CPU-bound work to the thread pool

The [reactor](../reference/glossary.md#concurrency) runs every computation on one thread. A
computation that calculates for a long time without [suspending](../reference/glossary.md#concurrency) (hashing a password, compressing a file, parsing a large document) stops every
other computation until it ends. `reactor.offload(fn, ...)` runs such a function on libuv's thread
pool instead and suspends only the caller. This guide is written for hecate 0.x and Lua 5.5;
call `offload` inside `reactor.run`, like every call that suspends.

## Run a function on the pool

`offload` takes the function and its arguments and returns the function's results:

<!-- example: packages/reactor/examples/hecate.reactor.offload.lua -->
```lua
-- A CPU-bound function runs on the libuv thread pool while the reactor keeps serving
-- other computations. The function is self-contained: what it needs arrives as
-- arguments, and its results are copied back.
local reactor = require("hecate.reactor")

reactor.run(function()
  local ticks = 0
  local ticker = reactor.fork(function()
    while true do
      reactor.sleep(0.001)
      ticks = ticks + 1 -- counted after a completed sleep: the reactor was free meanwhile
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

The function runs in the separate Lua state of a pool thread, with a fresh environment for each
call. It sees the standard libraries and `require`, but nothing of the reactor thread: no global of
yours, no loaded module, no reactor. The function must not call anything that suspends. A global it
assigns disappears with the call; do not change the standard library tables, which every later
call on that thread shares.

## Write a self-contained function

The function travels to the pool thread as bytecode, and the local variables it captures from the
surrounding code (its upvalues) do not travel with it. `offload` therefore refuses a function that
captures anything other than the global environment, with an `ArgumentError` that names the
variable:

```lua
local rounds = 10
reactor.offload(function() return rounds end) -- ArgumentError: captures the local variable rounds
reactor.offload(function(n) return n end, rounds) -- correct: the value is an argument
```

To use a module on the pool thread, `require` it inside the function. The pool thread searches the
paths of the `LUA_PATH` and `LUA_CPATH` environment variables, not a `package.path` your program
changed while running.

## Know what crosses

Arguments and results are copied from one Lua state to the other:

- `nil`, booleans, numbers (an integer stays an integer, a float stays a float) and strings, of
  any length and with any bytes;
- plain tables built from them: no metatable, keys that are booleans, numbers or strings, no
  table that contains itself, at most 100 levels of nesting.

A table reached twice is copied twice, so the copies are distinct tables. A function, a
coroutine, a userdata or a table with a metatable (an instance of a class, for example) cannot
cross: as an argument it raises `ArgumentError` before anything runs, as a result it raises
`reactor.OffloadError`. There is no limit on the number of arguments or results, and `nil`
values keep their place.

## Handle errors

An error raised by the function reaches the caller as a `reactor.OffloadError` with
`err.context.reason` set to `"raised"`. Its message starts with `reactor.offload:` followed by the
original message (the `message` field of an error object), `err.context.traceback` holds the
traceback on the pool thread, and `err.context.code` keeps the code of a hecate error. The original
error object stays on the pool thread. A result that cannot be copied gives the reason `"result"`.

```lua
-- In app.lua, line 12:
local ok, err = pcall(reactor.offload, function() error("corrupt input") end)
-- err.message: "reactor.offload: app.lua:12: corrupt input"
```

## Bound the work, not only the wait

A function that runs on the pool cannot be interrupted. When the caller is
[cancelled](../reference/glossary.md#concurrency), by `reactor.deadline` or by its
[scope](../reference/glossary.md#concurrency), it is released at once and the result is discarded
when it arrives, but the pool thread stays busy until the function returns, and `reactor.run` does
not return before it does. Give long work its own limit, for example a maximum input size or a
number of rounds.

## Size the pool

The pool has 4 threads by default and is shared with the file system and name resolution: four
long offloaded functions delay every `reactor.fs` call and every name resolution until one of them
returns. Set the environment variable `UV_THREADPOOL_SIZE` before the program starts to change the
size, and bound the number of concurrent offloads with a `reactor.Semaphore` when the work can
pile up:

```lua
local slots = reactor.Semaphore(2)

-- `slow_hash` is a self-contained function defined elsewhere: it is the argument of `offload`,
-- not a variable the offloaded function captures.

local function hash(password, salt)
  local permit <close> = slots:acquire()
  return reactor.offload(slow_hash, password, salt)
end
```

Each call copies its arguments and results and loads the function on the pool thread: a round trip
costs tens of microseconds, and copying a large table costs time on the reactor thread in proportion
to its size. Offload work of a millisecond or more, and keep short functions on the reactor thread.
