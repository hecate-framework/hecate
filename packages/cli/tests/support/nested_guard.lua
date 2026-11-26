-- A fake `run` for the unit tests of the commands that behaves like the real one, `reactor.run`, in the one way that
-- matters: a task cannot start another reactor from inside it. The commands call file system functions inside `run`; the
-- real `fs.read` of some of them wraps `reactor.run` itself and is only valid outside it, which `outside` enforces for
-- the fakes of those functions.
---@class hecate.cli.tests.NestedGuard
---@field inside boolean
---@field run fun(task: fun(): any): any
---@field outside fun(fn: function): function

local guard = { inside = false }

--- Runs `task` as the reactor would: raises when called from within another task.
function guard.run(task)
  if guard.inside then error("nested reactor: `run` was called inside a task that `run` is already running", 2) end
  guard.inside = true
  local results = table.pack(pcall(task))
  guard.inside = false
  if not results[1] then error(results[2], 0) end
  return table.unpack(results, 2, results.n)
end

--- Wraps a fake whose real counterpart starts a reactor of its own: it raises when called inside `run`.
function guard.outside(fn)
  return function(...)
    if guard.inside then error("nested reactor: this function starts a reactor and cannot be called inside `run`", 2) end
    return fn(...)
  end
end

return guard
