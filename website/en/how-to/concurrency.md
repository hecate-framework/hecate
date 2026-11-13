---
description: Run work concurrently with hecate.reactor - fork and join, scopes, select, deadlines, channels, and a mutex to protect state shared across suspension points.
hecate: "0.x"
lua: "5.5"
order: 18
---

# Concurrency: fork, join, select, deadlines, channels and shared state

This guide shows the concurrency primitives of `hecate.reactor` on small tasks. It is written for hecate 0.x and
Lua 5.5. For the model behind them, read [The concurrency model](../explanation/concurrency-model.md).

Every primitive below runs inside `reactor.run(fn)`, which runs `fn` in a managed
[coroutine](../reference/glossary.md#concurrency) and returns once it and everything it forked have finished. An
action of `hecate.http.Server` or of an `Application` already runs inside one. Outside a managed coroutine, a primitive
raises `NonYieldableContextError`.

## Run computations at the same time

`reactor.fork(fn, ...)` starts a [computation](../reference/glossary.md#concurrency) and returns a
[future](../reference/glossary.md#concurrency) at once. `reactor.join(f1, f2, ...)` waits for every future and returns
their first values, in argument order.

<!-- example: packages/reactor/examples/hecate.reactor.join.lua -->
```lua
-- Fork computations, then join them: `join` returns their values in
-- argument order. Inside a scope, a computation that fails cancels its
-- siblings, and the scope raises the failure once every child has ended.
local reactor = require("hecate.reactor")

local function fetch(name, seconds)
  reactor.sleep(seconds) -- stands for a request to another service
  return name .. " ready"
end

reactor.run(function()
  local users = reactor.fork(fetch, "users", 0.02)
  local orders = reactor.fork(fetch, "orders", 0.01)
  print(reactor.join(users, orders))
  -- Prints: users ready	orders ready

  local slow
  local ok, err = pcall(reactor.scope, function(scope)
    slow = scope:fork(fetch, "report", 10)
    local failing = scope:fork(function()
      reactor.sleep(0.01)
      error("no stock", 0)
    end)
    return reactor.join(slow, failing)
  end)
  print(ok, err, slow:state())
  -- Prints: false	no stock	cancelled
end)
```

The two fetches of the first part overlap: the `join` takes about 20 milliseconds, not 30.

A computation belongs to the [scope](../reference/glossary.md#concurrency) that was running when it was forked.
`reactor.scope(fn)` opens a scope of its own and returns only when every computation forked inside has ended. When
one fails, the scope cancels the others and raises the first failure, as the second part of the example shows. Use a
scope whenever you want to handle the failure of a group: the failure of a computation forked directly in an outer
scope fails that outer scope, even if you catch the error of `join`.

A future also has `value()` (waits for its result), `cancel()`, `done()` and `state()`, one of `pending`,
`completed`, `failed` and `cancelled`.

## Wait for the first result

`reactor.select(...)` waits for the first of several alternatives, returns its position and its value, and cancels
the futures that lost. An alternative is a future or a channel operation.

<!-- example: packages/reactor/examples/hecate.reactor.select.lua -->
```lua
-- `select` waits for the first of several alternatives and cancels the
-- futures that lost. `deadline` bounds a computation in time.
local core = require("hecate.core")
local reactor = require("hecate.reactor")

local function fetch(name, seconds)
  reactor.sleep(seconds)
  return name
end

reactor.run(function()
  -- The first mirror to answer wins; the other one is cancelled.
  local index, value = reactor.select(
    reactor.fork(fetch, "mirror-a", 0.05),
    reactor.fork(fetch, "mirror-b", 0.01))
  print(index, value)
  -- Prints: 2	mirror-b

  -- A channel operation is an alternative too: here, a stop request.
  local jobs, stop = reactor.Channel(0), reactor.Channel(0)
  reactor.fork(function() stop:send("stop") end)
  print(reactor.select(jobs:receive_op(), stop:receive_op()))
  -- Prints: 2	stop

  -- `deadline` returns the results of the function, or raises when late.
  print(reactor.deadline(1, fetch, "in time", 0.01))
  -- Prints: in time
  local ok, err = pcall(reactor.deadline, 0.01, fetch, "late", 10)
  print(ok, core.name(err))
  -- Prints: false	DeadlineExceededError
end)
```

When several alternatives are ready at once, the first in argument order wins: the order is a priority, not a random
choice. A channel operation takes effect only when it is the one selected, so a losing `receive_op()` takes no value
and a losing `send_op(v)` sends nothing.

## Bound the time

`reactor.deadline(limit, fn, ...)` runs `fn` and returns its results, or cancels it and raises
`DeadlineExceededError` when it is late. `limit` is a [timeout](../reference/glossary.md#concurrency) in seconds or
an instant from `reactor.at(seconds)`. Use an instant to share one [deadline](../reference/glossary.md#concurrency)
between several steps:

```lua
local finish = reactor.at(reactor.now() + 2)
local user = reactor.deadline(finish, load_user, id)
local orders = reactor.deadline(finish, load_orders, id)
```

A deadline is delivered at suspension points. Pure computation that never suspends is not interrupted; move it to
the thread pool with [`reactor.offload`](offload-cpu-bound-work.md). What a cancelled read or write leaves behind is
in [Deadlines and cancellation on streams](deadlines-and-cancellation.md).

## Pass values through a channel

A [channel](../reference/glossary.md#concurrency) carries values between coroutines. `reactor.Channel(capacity)`
holds up to `capacity` values; with capacity 0, each `send` waits for a `receive` (a rendezvous).

<!-- example: packages/reactor/examples/hecate.reactor.Channel.lua -->
```lua
-- A channel carries values from producers to consumers. A full channel
-- suspends its sender (back-pressure); a closed one is drained, then
-- `receive` raises `ClosedChannelError`.
local core = require("hecate.core")
local reactor = require("hecate.reactor")

reactor.run(function()
  local queue = reactor.Channel(2) -- holds at most two values
  local producer = reactor.fork(function()
    for n = 1, 5 do queue:send(n) end
    queue:close()
  end)
  local sum = 0
  while true do
    local ok, value = pcall(queue.receive, queue)
    if not ok then
      print(core.name(value))
      -- Prints: ClosedChannelError
      break
    end
    sum = sum + value
  end
  reactor.join(producer)
  print(sum)
  -- Prints: 15
end)
```

- `send` suspends while the channel is full: a fast producer waits for a slow consumer
  ([back-pressure](../reference/glossary.md#concurrency)).
- `close()` ends the channel. Receivers first take the values still buffered, then `receive` raises
  `ClosedChannelError`. A `send` on a closed channel raises it too.
- `length()` and `capacity()` tell how full it is.

To limit how many computations do something at once (calls to a remote service, for example), use a
[semaphore](../reference/glossary.md#concurrency): `local permit <close> = semaphore:acquire()` waits for one of its
`n` units and gives it back when `permit` goes out of scope.

## Protect shared state

The reactor runs one coroutine at a time, so code between two suspension points is never interleaved with other
code. A read-modify-write sequence that suspends in the middle is not safe: another coroutine can run at that point
and change the same state.

<!-- example: packages/reactor/examples/hecate.reactor.Mutex.lua -->
```lua
-- Coroutines run one at a time, but a read-modify-write that spans a
-- suspension point can interleave with another one. A mutex makes the
-- sequence exclusive; its permit is released when it goes out of scope.
local reactor = require("hecate.reactor")

reactor.run(function()
  local balance = 100
  local function withdraw(amount)
    local current = balance
    reactor.sleep(0.001) -- a suspension point: another coroutine runs
    balance = current - amount
  end
  reactor.join(reactor.fork(withdraw, 30), reactor.fork(withdraw, 20))
  print(balance) -- one update is lost
  -- Prints: 80

  balance = 100
  local mutex = reactor.Mutex()
  local function withdraw_exclusively(amount)
    local permit <close> = mutex:lock()
    local current = balance
    reactor.sleep(0.001)
    balance = current - amount
  end
  reactor.join(reactor.fork(withdraw_exclusively, 30),
    reactor.fork(withdraw_exclusively, 20))
  print(balance)
  -- Prints: 50
end)
```

`mutex:lock()` waits until the [mutex](../reference/glossary.md#concurrency) is free and returns a permit. A
`<close>` variable releases it when the block ends, by return or by error. Waiters get the mutex in arrival order.

Prefer designs that need no lock:

- keep state local to a request, or in a scoped service of the container
  ([Use the container](use-the-container.md));
- give the state to one computation and send it messages through a channel;
- do not suspend inside a read-modify-write sequence.

State in one process is not shared with the other [workers](../reference/glossary.md#concurrency) of a
multi-process server: shared state belongs in a database.

For a condition to wait on, `reactor.Monitor()` gives a [monitor](../reference/glossary.md#concurrency) and its
conditions. It follows Mesa semantics: a woken waiter must test its condition again in a `while` loop.

## Avoid the traps

- **A detached computation outlives its scope.** `reactor.detach(fn)` starts `fn` in the application scope. Its
  failure is seen only through its future, or through the `on_unobserved_failure` option of the reactor when nothing
  waits for it. Use it for work that must survive the request, and only then.
- **Some calls cannot suspend.** The comparator of `table.sort`, the replacement function of `string.gsub`, some
  metamethods called from C and a module being loaded by `require` cannot suspend. A suspending call there raises
  `NonYieldableContextError`.
- **Cleanup in a cancelled scope cannot suspend**, unless it runs in `reactor.shield(limit, fn)`. See
  [Run cleanup while the scope is cancelled](deadlines-and-cancellation.md#run-cleanup-while-the-scope-is-cancelled).

## See also

- [The concurrency model](../explanation/concurrency-model.md)
- [Offload CPU-bound work to the thread pool](offload-cpu-bound-work.md)
- Reference: [`hecate.reactor`](../reference/reactor/index.md)
