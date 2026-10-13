---
title: reactor.sleep
description: Suspends the running coroutine for a duration of the reactor clock.
hecate: "0.x"
lua: "5.5"
---

# reactor.sleep

Suspends the running coroutine for `seconds` of the reactor clock.

## Syntax

```lua
---@async
---@param seconds number
function reactor.sleep(seconds) end
```

## Parameters and return values

| Name | Type | Description |
|---|---|---|
| `seconds` | `number` | Finite and not negative. `0` yields to the other ready coroutines. |

Returns nothing.

## Errors

- `hecate.core.ArgumentError` when `seconds` is not a finite number greater than or equal to 0.
- `hecate.core.NonYieldableContextError` when called outside a managed coroutine.
- `hecate.core.DeadlineExceededError` when an enclosing deadline expires while suspended.

## Suspension

`sleep` **suspends** (`---@async`). It is a cancellation point: if the enclosing scope is
cancelled, the timer is withdrawn and `<close>` handlers run.

## Examples

```lua
local reactor = require("hecate.reactor")

reactor.run(function()
  local f = reactor.fork(function()
    reactor.sleep(0.1)
    return "done"
  end)
  print(reactor.join(f))
end)
```

## Specifications

None: a hecate primitive (see Hoare, *CSP*, 1978, for the underlying model).

## Compatibility

Introduced in hecate 0.1. Lua 5.5.

## See also

- [Concurrency in hecate](../guide/concurrency.md)
