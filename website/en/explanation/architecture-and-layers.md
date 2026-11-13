---
description: How hecate is built - packages in layers with no upward dependency, Lua first and native code only where needed, the life of a request, and a boot that validates everything before serving.
hecate: "0.x"
lua: "5.5"
order: 6
---

# Architecture and layers

This page explains how hecate is divided into packages, and why. It then follows a request through those packages,
and shows what happens at boot. It is written for hecate 0.x and Lua 5.5.

## One framework, many packages

hecate is one framework made of packages. Each package is one rock, `hecate-<name>`, with one Lua module root,
`hecate.<name>`. You load a package by its module root:

```lua
local hecate = require("hecate")
local core = require("hecate.core")
local schema = require("hecate.schema")
```

The meta-module `hecate` re-exports what a typical application needs: `Application`, `Controller`, `routes`,
`respond` and `problem`. Application code can therefore start with one `require`.

The meta-module does not re-export the object model. Classes are declared with `core.class` from `hecate.core`.
Schemas are built with `hecate.schema`.

All packages share one object model, one error hierarchy, one logging package and one configuration. No package
brings a parallel mechanism of its own. A controller, a service and an error are all classes of `hecate.core`.

## Layers

Packages are arranged in layers. A package depends only on packages of a lower layer or of its own layer. It never
depends on them in a cycle. A check of the repository refuses an upward dependency.

| Layer | Packages | Role |
|---|---|---|
| 0 Foundation | `core` | object model, errors, enumerations |
| 1 Runtime | `reactor`, `net`, `json`, `log` | the reactor and its transport, streams and TLS, JSON, structured logging |
| 2 Protocol | `http`, `router`, `schema`, `websocket` | HTTP/1.1 server and client, routing, schemas |
| 3 Framework | `config`, `container`, `kernel`, `openapi`, `security`, `template` | configuration, container, the application, contracts |
| Data | `query`, `sql`, the database drivers, `orm`, `migration`, `redis`, `mongodb` | data access |
| Tooling | `test`, `doc`, `cli` | tests, documentation, the command line |
| Meta | `hecate` | re-exports of the framework surface |

Two terms of this table recur on every page. The [reactor](../reference/glossary.md#concurrency) is the scheduler
that dispatches I/O events to the code waiting for them. The [container](../reference/glossary.md#object-model-and-architecture)
is the object that resolves and constructs the dependencies of an application.

Not every package exists yet. `websocket`, `openapi`, `security` and `template` are specified and planned for later
phases. So are the data packages, and the tooling packages except a first part of `doc`.

### Why layers

The layers keep each package usable on its own. `router` depends only on `core`. It compiles a route table and
matches paths, and knows nothing of HTTP connections. Here it is used without any server:

<!-- example: packages/router/examples/hecate.router.Router.lua -->
```lua
-- Declare routes as data, compile them once, match requests and build URLs
-- from route names.
local router = require("hecate.router")

local routes = router.Router({
  { method = "GET", path = "/users", name = "users.list" },
  { method = "GET", path = "/users/{id}", name = "users.show" },
  { method = "DELETE", path = "/users/{id}", name = "users.delete" },
  { method = "GET", path = "/users/me", name = "users.me" },
  { method = "GET", path = "/static/{path...}", name = "static" },
})

-- A match carries the route and its parameters, or the status to answer.
local function show(method, path)
  local match = routes:match(method, path)
  if match.status == 200 then
    return method, path, match.route.name, match.parameters.id or match.parameters.path or "-"
  end
  return method, path, match.status, match.allow_field or "-"
end

print(show("GET", "/users/42"))
-- Prints: GET	/users/42	users.show	42
print(show("GET", "/users/me"))
-- Prints: GET	/users/me	users.me	-
print(show("DELETE", "/users/me"))
-- Prints: DELETE	/users/me	users.delete	me
print(show("POST", "/users/42"))
-- Prints: POST	/users/42	405	DELETE, GET, HEAD, OPTIONS
print(show("GET", "/static/css/site.css"))
-- Prints: GET	/static/css/site.css	static	css/site.css
print(show("GET", "/nothing"))
-- Prints: GET	/nothing	404	-
print(routes:url_for("users.show", { id = "Ada Lovelace" }))
-- Prints: /users/Ada%20Lovelace
```

`http` is the mirror image: it serves requests and knows nothing of routes. `kernel`, in the framework layer, joins
the two. You can use `hecate.http` without the kernel, or `hecate.schema` in a program that is not a server.

## Lua first

hecate is written in Lua. Native code is used only where Lua cannot reach the performance or the system access
needed:

| Need | Native component |
|---|---|
| asynchronous I/O | libuv, through the luv binding |
| HTTP/1.1 parsing | llhttp |
| JSON | the yyjson decoder (C) and the serde_json encoder (Rust) |
| TLS | rustls |

Only `reactor` loads luv. The other packages reach the operating system through it, so they need no native code of
their own.

Database protocols are planned in Lua on top of `hecate.net`, for the same reason. They will then cooperate with the
reactor and need no build per platform.

## The life of a request

A request crosses several packages between the moment it arrives and the moment its response leaves. Here are the
steps, in order:

1. The reactor reports that a connection is readable. `http.Server` parses the request head with llhttp.
2. The server runs the action of the application in a new [coroutine](../reference/glossary.md#concurrency), Lua's
   native unit of execution. The coroutine runs inside a [scope](../reference/glossary.md#concurrency) of its own
   for this request: a region that owns every computation forked inside it.
3. The global [filters](../reference/glossary.md#object-model-and-architecture) of the application run. A filter is
   one element of the chain around an action: it sees the request before the action and the result after it.
4. Inside them, the guard catches errors, and the router matches the method and the path. A request that matches
   nothing gets a `404`, `405` or `400` problem response. That response flows back through the global filters.
5. The filters of the feature module, of the controller and of the route run.
6. The kernel coerces and validates the path parameters, query, header fields, cookies and content against the
   schemas of the route. A failure is a `422` problem response.
7. The [action](../reference/glossary.md#object-model-and-architecture) runs. The action is the function that
   serves the request: a controller method or a function. It returns a value, a `Response` or a problem.
8. The kernel serialises the result into a
   [representation](../reference/glossary.md#object-model-and-architecture), the transferable form of a resource
   state. In development and test, it also validates the result against the response schema.
9. The server writes the response. Writing suspends until the bytes are handed to the system.

The order of steps 3 to 7 shows in this example. Each filter records its name on the way in and on the way out:

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

The inputs are validated after the filters, just before the action. A filter that refuses a request (authentication,
for example) therefore costs no read of its content.

The request scope does not end before every computation forked while serving the request has ended. Background work
cannot outlive its request unnoticed.

[Filters](../how-to/filters.md) and [Map domain errors to problem details](../how-to/map-domain-errors-to-problem-details.md)
show steps 3 to 8 in practice.

## A boot that validates everything

Boot is where everything that can fail before the first request is checked. A typo in a binding name or a path
parameter fails when you start the program, not when a client finds it.

The [configuration](../reference/glossary.md#configuration) is loaded first, by `hecate.load_configuration`. The
configuration is the immutable, validated key-value tree a process is booted with. Loading merges its layers and
validates the result against its schema, or raises.

`Application:boot()`, which `serve()` calls, then does the rest of the work that can fail:

1. Order the feature modules after the modules they require. Refuse a duplicate, a cycle or a missing module.
2. Bind the services and validate the container graph: missing bindings and cycles.
3. Collect the controllers and route modules into one route table. Check that every action is a method of its
   controller.
4. Build the dispatcher: compile the router, resolve the schemas of every route, check the binding names that
   controllers declare as dependencies, and compose the filter chain of every route.

Schemas and route declarations are checked earlier still: when they are declared, as the modules that hold them load.

Any failure stops the boot with a precise error. Nothing is checked for the first time at the first request.

A failed boot also changes no process-wide setting.

With several workers, the [primary](../reference/glossary.md#concurrency) boots the application once before it
starts any worker. The primary is the process that starts and supervises the workers. A boot error is therefore
reported once. See [Multi-process serving](multi-process-serving.md).

## See also

- [The object model](object-model.md)
- [The concurrency model](concurrency-model.md)
- [The HTTP model](http-model.md)
