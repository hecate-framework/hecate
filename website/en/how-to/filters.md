---
description: Wrap actions with filters, the chain of responsibility of hecate.kernel - the four layers and their order, short-circuits, authentication and CORS written as filters, and what is not available yet.
hecate: "0.x"
lua: "5.5"
order: 17
---

# Filters

This guide shows how to wrap the actions of an application with filters. It is written for hecate 0.x and Lua 5.5.
It assumes you know how to declare routes with `hecate.routes` or a
[controller](../reference/glossary.md#object-model-and-architecture), a class whose methods are actions.

An [action](../reference/glossary.md#object-model-and-architecture) is the function that serves a request. A
[filter](../reference/glossary.md#object-model-and-architecture) wraps the action of a route. It sees the request on
the way in and the result on the way out. It can also stop the request before the action.

## Write a filter

A filter is any table with a `handle(self, request, next)` function. It can be a plain table or an instance of a
class. Here is the smallest filter, one that passes the request on:

```lua
local pass_through = {
  handle = function(self, request, next)
    local result = next(request)  -- the rest of the chain, then the action
    return result
  end,
}
```

`next` runs the rest of the chain, then the action. The filters of a request form a
[chain of responsibility](../reference/glossary.md#object-model-and-architecture): an ordered list of handlers around
the action, each one deciding whether to call the next.

In `handle`, a filter can do three things:

- **pass** the request on, `return next(request)`, possibly after changing it;
- **short-circuit**: return a result without calling `next`, so the action never runs;
- **post-process**: change what `next` returned before returning it.

An error raised by a filter is handled like an error of the action. The guard turns it into
[problem details](map-domain-errors-to-problem-details.md).

The chain is composed once, at boot. So a filter costs no allocation per request.

Nothing stops a filter from calling `next` twice. Do it only on purpose.

## Attach filters at four layers

You attach a filter where it should apply. There are four layers:

| Layer | Where | Applies to |
|---|---|---|
| global | `filters` option of `Application` | every request, including those that match no route |
| feature module | `filters` field of the module table | the routes of that module |
| controller | class field `filters` of the controller | the routes of that controller |
| route | `filters` field of the route declaration | that route |

A [feature module](../reference/glossary.md#object-model-and-architecture) is the kernel's grouping of routes into one
feature.

The order is global, module, controller, then route, outermost first. Inside a list, the first filter is the
outermost. The example traces one filter of each layer:

<!-- example: packages/hecate/examples/hecate.Application.filters.lua -->
```lua
-- The order of the filter chain: the filters of the application, of the
-- feature module, of the controller, then of the route, outermost first.
-- Each filter sees the request on the way in and the result on the way out.
local core = require("hecate.core")
local http = require("hecate.http")
local hecate = require("hecate")

-- A filter is any table with a `handle(self, request, next)` function.
local trail = {}
local function trace(name)
  return {
    handle = function(_, request, next)
      trail[#trail + 1] = name
      local result = next(request)
      trail[#trail + 1] = "/" .. name
      return result
    end,
  }
end

local Reports = core.class("Reports", hecate.Controller)
Reports.prefix = "/reports"
Reports.filters = { trace("controller") }
hecate.Controller.route(Reports, {
  method = "GET", path = "/daily", action = "daily",
  filters = { trace("route") },
})
function Reports:daily()
  trail[#trail + 1] = "action"
  return { total = 42 }
end
core.finalise(Reports)

local app = hecate.Application({
  filters = { trace("global") },
  modules = {
    { name = "reporting", routes = { Reports }, filters = { trace("module") } },
  },
})
local serve = app:boot()

local function get(target)
  trail = {}
  local request = http.Request({
    method = "GET", target = target, fields = http.Fields(),
  })
  return serve(request).status
end

print(get("/reports/daily"))
-- Prints: 200
print(table.concat(trail, " ", 1, 5))
-- Prints: global module controller route action
print(table.concat(trail, " ", 6))
-- Prints: /route /controller /module /global

-- Only the global filters see a request that matches no route.
print(get("/nothing"))
-- Prints: 404
print(table.concat(trail, " "))
-- Prints: global /global
```

A route module has no layer of its own. The `filters` option of `hecate.routes(name, { filters = ... })` gives the
*default* filters of its routes:

- a route that declares `filters` replaces them;
- a route that declares `filters = {}` removes them.

The filters of a controller, by contrast, always run, before those of the route.

## Know what each layer sees

The global filters wrap the routing step. They see every request. The `404`, `405` and `400` problem responses pass
through them, and so does the automatic answer to `OPTIONS`.

When the global filters run, the route is not known yet. `request.parameters.path` is empty, and `request.services`
is not set.

The other layers run after routing. There:

- `request.services` is the [service scope](../reference/glossary.md#object-model-and-architecture) of the request,
  when the application has a container. A service scope is the region in which a `scoped` service has one instance.
- `request.parameters.path` holds the path parameters as raw strings.
- The inputs are not validated yet. The kernel coerces and validates the path, query, header fields, cookies and
  content after the last filter, just before the action.

So a request refused by a filter costs no read of its content.

What `next` returns depends on the layer:

- For a **global** filter, `next` returns a `hecate.http.Response`. The result is already serialised, and an error
  is already a problem response.
- For a **module, controller or route** filter, `next` returns what the action returned: a value, a `Response` or a
  problem. The serialisation happens after the chain.

So a filter that sets response header fields is a global filter. A filter of another layer that does it must
handle each kind of result.

A response whose content is a function is written after the chain has returned. A filter can set its fields. It
cannot read or change its content.

## Authenticate with a filter

Authentication is a filter of the routes that need it. The example below refuses a request without a known bearer
token. It answers `401` with its `WWW-Authenticate` field. Otherwise it passes the user on to the action.

The same example also contains the CORS filter of the next section.

<!-- example: packages/hecate/examples/hecate.filter.authentication_and_cors.lua -->
```lua
-- Two filters written with the kernel of today: authentication, which
-- refuses a request before the action runs, and CORS, which answers the
-- preflight request and marks every response of an allowed origin.
local http = require("hecate.http")
local hecate = require("hecate")

-- Authentication: a filter of the routes that need it. It short-circuits
-- with a 401 (RFC 9110 asks for WWW-Authenticate) or passes the principal.
---@class app.Request : hecate.kernel.Request
---@field principal string?  set by the authentication filter

local TOKENS = { ["s3cret"] = "ada" }
local authenticate = {
  handle = function(_, request, next)
    local token = (request.fields:get("Authorization") or "")
      :match("^Bearer (%S+)$")
    local user = token and TOKENS[token]
    if user == nil then
      local refused = http.problem.response(401, "A bearer token is needed.")
      refused.fields:set("WWW-Authenticate", 'Bearer realm="accounts"')
      return refused
    end
    request.principal = user
    return next(request)
  end,
}

-- CORS: a global filter, because the preflight OPTIONS request matches no
-- declared route and only the global filters see it.
local ALLOWED = "https://app.example.com"
local cors = {
  handle = function(_, request, next)
    local origin = request.fields:get("Origin")
    if origin ~= ALLOWED then return next(request) end
    local response
    if request.method == "OPTIONS"
      and request.fields:get("Access-Control-Request-Method") then
      response = http.Response(204)
      response.fields:set("Access-Control-Allow-Methods", "GET, POST")
      response.fields:set("Access-Control-Allow-Headers", "Authorization")
      response.fields:set("Access-Control-Max-Age", "600")
    else
      -- Global filters receive a Response: the result is serialised.
      response = next(request)
    end
    response.fields:set("Access-Control-Allow-Origin", origin)
    response.fields:add("Vary", "Origin")
    return response
  end,
}

-- The filters of a route module are the default filters of its routes.
local accounts = hecate.routes("accounts", { filters = { authenticate } })
accounts:get("/me", {
  ---@param request app.Request
  action = function(request) return { user = request.principal } end,
})

local serve = hecate.Application({ routes = { accounts }, filters = { cors } })
  :boot()
local function ask(method, fields)
  return serve(http.Request({
    method = method, target = "/me", fields = http.Fields(fields),
  }))
end

local response = ask("GET", { Authorization = "Bearer s3cret" })
print(response.status, response.content)
-- Prints: 200	{"user":"ada"}
response = ask("GET", {})
print(response.status, response.fields:get("WWW-Authenticate"))
-- Prints: 401	Bearer realm="accounts"
response = ask("OPTIONS", {
  Origin = ALLOWED, ["Access-Control-Request-Method"] = "GET",
})
print(response.status, response.fields:get("Access-Control-Allow-Methods"))
-- Prints: 204	GET, POST
response = ask("GET", { Origin = ALLOWED })
print(response.status, response.fields:get("Access-Control-Allow-Origin"))
-- Prints: 401	https://app.example.com
```

The filter stores the user on the request (`request.principal`). That is a plain field of your own. The `security`
package, which will provide authentication filters, does not exist yet.

In a real application, compare tokens from a store in constant time. The table lookup above is only an
illustration.

To refuse with a body only, without a header field, a filter can also return a problem:

```lua
return hecate.problem.Forbidden { detail = "No access to this account." }
```

The serialisation after the chain answers it.

## Answer CORS with a filter

The `cors` filter of the example is global, for two reasons:

- The preflight request (`OPTIONS` with `Access-Control-Request-Method`) matches no declared route. Only the global
  filters see it.
- A global filter receives a `Response`. So it can set the `Access-Control-Allow-Origin` field on every answer, a
  `401` from an inner filter included.

Add `Vary: Origin`, so that a cache keeps one answer per origin.

## What does not exist yet

**Compression.** hecate has no compression codec. A filter could replace the content of a response with a compressed
one. But the codec would be a third-party dependency, which needs an architecture decision first. This guide shows
none.

**Request identifiers.** Binding a request id in the [ambient context](../reference/glossary.md#concurrency) is
designed (ADR 0025) and deferred. The ambient context holds the bindings visible to a running computation, inherited
by the computations it forks or detaches. With a bound request id, every log record of a request would carry it. The
kernel does not do it yet.

Meanwhile, a global filter can read or create an `X-Request-Id` field and set it on the response. The call
`log.bind({ request_id = id }, next, request)` binds the id for the records written while the rest of the chain runs.
See [Log structured records](log-structured-records.md).

**Built-in filters.** No access log, CORS, rate limiting or authentication filter ships with the kernel. The access
log is the `on_response` hook of the server (see `examples/hello`).

## See also

- [Map domain errors to problem details](map-domain-errors-to-problem-details.md)
- [Use the container](use-the-container.md): services resolved in `request.services`.
- [Log structured records](log-structured-records.md)
