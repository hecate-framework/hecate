-- Shared state of the running reactor, kept in one place so that `Future` and `Scope`
-- can suspend and cancel without requiring the scheduler module (which requires them).
-- Only `hecate.reactor` modules touch this table; it is not public API.
global <const> type

---@class hecate.reactor.internal.Context
---@field reactor? table  the running `Reactor`, or nil outside `Reactor:run`
---@field suspend? fun(register?: fun(wake: fun(...): boolean): (fun()?), uncancellable?: boolean, operation?: string): ...
---@field notify_cancel? fun(computation: table)  wakes a suspended, cancellable computation whose cancellation is pending
---@field current_computation? fun(operation: string): table  the running computation, or raises when none is running
---@field scope_run? fun(fn: function, deadline_at?: number): ...  runs a function in a new scope (set by `primitives`)
---@field cancel_computation? fun(computation: table, err: any)  requests cancellation of one computation
local context = {}

return context
