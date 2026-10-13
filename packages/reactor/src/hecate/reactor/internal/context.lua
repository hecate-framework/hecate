-- Shared state of the running reactor, kept in one place so that `Future` and `Scope`
-- can suspend and cancel without requiring the scheduler module (which requires them).
-- Only `hecate.reactor` modules touch this table; it is not public API.
global <const> type

---@class hecate.reactor.internal.Context
---@field reactor? table  the running `Reactor`, or nil outside `Reactor:run`
---@field suspend? fun(register?: fun(wake: fun(...): boolean): (fun()?), uncancellable?: boolean): ...
---@field notify_cancel? fun(task: table)  wakes a suspended, cancellable task whose cancellation is pending
---@field current_task? fun(operation: string): table  the running task, or raises when none is running
---@field scope_run? fun(fn: function, deadline_at?: number): ...  runs a function in a new scope (set by `primitives`)
---@field cancel_task? fun(task: table, err: any)  requests cancellation of one task
local context = {}

return context
