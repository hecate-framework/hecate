-- The chain of responsibility around an action (http-and-routing.md, "Filters"; ADR 0006).
global <const> require, type, error

local core = require("hecate.core")

--- A request as filters and actions of the kernel see it: a `hecate.http.Request` plus what the kernel injects. The
--- injected fields are set by the dispatcher, in this order: `services` before the chain of a matched route, then the
--- values read by the schemas of the route just before the action (so filters of the chain see the raw ones). For a
--- request that matches no route (the 404, 405, 400 and `OPTIONS` answers that global filters also see) none is set.
--- `scope` stays what `hecate.http.Server` sets: the reactor scope of the request.
---@class hecate.kernel.Request : hecate.http.Request
---@field services hecate.container.ServiceScope?  the service scope of the request, set when the application has a container; resolves the services of the route (`request.services:resolve("name")`) and is closed when the request ends
---@field parameters { path: table<string, any>, query: table<string, any>, fields: table<string, any>, cookies: table<string, any> }  the values declared by the route, by location: decoded path parameters (strings, until the action), then, in the action, `path`, `query`, `fields` (header fields) and `cookies` coerced and validated by the schemas of the route
---@field content? any  in the action, the content validated by the schema declared for `application/json` (an instance for a schema bound to a class); `read_content` and `stream_content` then raise `ContentError` (`consumed`)

--- A filter: one element of the chain of responsibility around an action. Any table with a
--- `handle` function qualifies (a class instance or a plain object).
---@class hecate.kernel.Filter
---@field handle fun(self: hecate.kernel.Filter, request: hecate.kernel.Request, next: fun(request: hecate.kernel.Request): any): any

--- A function that serves a request: an action, or an action wrapped by filters.
---@alias hecate.kernel.Action fun(request: hecate.kernel.Request): ...any

--- The chain of responsibility: composes filters around an action.
---@class hecate.kernel.chain
local chain = {}

--- Tells whether a value is a filter: a table with a `handle` function.
---@param value any
---@return boolean
function chain.is_filter(value)
  return type(value) == "table" and type(value.handle) == "function"
end

--- Composes filters around an action, once (at boot), and returns the function that serves
--- a request. The first filter of the list is the outermost: it sees the request first and
--- the result last. A filter may short-circuit (not call `next`), transform the request it
--- passes to `next`, or post-process the result `next` returns; every result of `next` is
--- passed through. `next` is a closure created here, one per filter, never per request, so a
--- request allocates nothing for the chain. For the same reason `next` may be called more
--- than once (a retrying filter); calling it twice is not detected. An error raised by a
--- filter or by the action propagates unchanged; mapping it to problem details is the
--- caller's business. An empty list returns `action` itself. The list is copied: later
--- changes to it have no effect. The order of the scopes (global, module, controller, route)
--- is decided by the caller, who passes one flat list.
---
--- Raises `hecate.core.ArgumentError` if `filters` is not a list, `action` is not a function,
--- or an element is not a filter (`context.index` gives its position).
---@param filters hecate.kernel.Filter[]  outermost first
---@param action hecate.kernel.Action
---@return hecate.kernel.Action serve  the action wrapped by the filters
function chain.compose(filters, action)
  if type(filters) ~= "table" then
    error(core.ArgumentError { message = "hecate.kernel.chain.compose: filters must be a list of filters, got " .. type(filters), context = { got = type(filters) } }, 2)
  end
  if type(action) ~= "function" then
    error(core.ArgumentError { message = "hecate.kernel.chain.compose: action must be a function, got " .. type(action), context = { got = type(action) } }, 2)
  end
  local count = #filters
  for index = 1, count do
    if not chain.is_filter(filters[index]) then
      error(core.ArgumentError {
        message = ("hecate.kernel.chain.compose: element %d of the filter list is not a filter (a table with a handle function), got %s"):format(
          index, type(filters[index])),
        context = { index = index, got = type(filters[index]) },
      }, 2)
    end
  end
  local serve = action
  for index = count, 1, -1 do
    local filter, inner = filters[index], serve
    serve = function(request) return filter:handle(request, inner) end
  end
  return serve
end

return chain
