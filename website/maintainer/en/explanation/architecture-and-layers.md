---
description: How hecate is built - packages in layers with no upward dependency, Lua first and native code only where needed, the life of a request, and a boot that validates everything before serving.
hecate: "0.x"
lua: "5.5"
order: 6
---

# Architecture and layers

This page explains how hecate is divided into packages and why, how a request travels through them, and what
happens at boot. It is written for hecate 0.x and Lua 5.5.

## One framework, many packages

hecate is one framework made of packages. Each package is one rock, `hecate-<name>`, with one Lua module root,
`hecate.<name>` (`require "hecate.router"`). The meta-module `hecate` re-exports what a typical application needs
(`Application`, `Controller`, `routes`, `respond`, `problem`), so that application code starts with one `require`.
It does not re-export the object model: classes are declared with `core.class` from `hecate.core`, and schemas are
built with `hecate.schema`.

All packages share one object model, one error hierarchy, one logging package and one configuration. No package
brings a parallel mechanism of its own: a controller, a service and an error are all classes of `hecate.core`.

## Layers

Packages are arranged in layers. A package depends only on packages of a lower layer or of its own layer, and never
in a cycle. A check of the repository refuses an upward dependency.

| Layer | Packages | Role |
|---|---|---|
| 0 Foundation | `core` | object model, errors, enumerations |
| 1 Runtime | `reactor`, `net`, `json`, `log` | the [reactor](../reference/glossary.md#concurrency) and its transport, streams and TLS, JSON, structured logging |
| 2 Protocol | `http`, `router`, `schema`, `websocket` | HTTP/1.1 server and client, routing, schemas |
| 3 Framework | `config`, `container`, `kernel`, `openapi`, `security`, `template` | configuration, [container](../reference/glossary.md#object-model-and-architecture), the application, contracts |
| Data | `query`, `sql`, the database drivers, `orm`, `migration`, `redis`, `mongodb` | data access |
| Tooling | `test`, `doc`, `cli` | tests, documentation, the command line |
| Meta | `hecate` | re-exports of the framework surface |

Not every package exists yet. `websocket`, `openapi`, `security`, `template`, the data packages and the tooling
packages (except a first part of `doc`) are specified and planned for later phases.

The layers keep each package usable on its own. `router` depends only on `core`: it compiles a route table and
matches paths, and knows nothing of HTTP connections. `http` serves requests and knows nothing of routes. `kernel`,
in the framework layer, joins them. You can use `hecate.http` without the kernel, or `hecate.schema` in a program
that is not a server.

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
their own. Database protocols are planned in Lua on top of `hecate.net`, for the same reason: they then cooperate with
the reactor and need no build per platform.

## The life of a request

1. The reactor reports that a connection is readable. `http.Server` parses the request head with llhttp.
2. The server runs the action of the application in a new [coroutine](../reference/glossary.md#concurrency), inside
   a [scope](../reference/glossary.md#concurrency) of its own for this request.
3. The global [filters](../reference/glossary.md#object-model-and-architecture) of the application run.
4. Inside them, the guard catches errors, and the router matches the method and the path. A request that matches
   nothing gets a `404`, `405` or `400` problem response, which flows back through the global filters.
5. The filters of the feature module, of the controller and of the route run.
6. The kernel coerces and validates the path parameters, query, header fields, cookies and content against the
   schemas of the route. A failure is a `422` problem response.
7. The [action](../reference/glossary.md#object-model-and-architecture) runs: a controller method or a function. It
   returns a value, a `Response` or a problem.
8. The kernel serialises the result into a
   [representation](../reference/glossary.md#object-model-and-architecture), validating it against the response
   schema in development and test.
9. The server writes the response. Writing suspends until the bytes are handed to the system.

The inputs are validated after the filters, just before the action: a filter that refuses a request (authentication,
for example) costs no read of its content. The request scope does not end before every computation forked while
serving the request has ended, so background work cannot outlive its request unnoticed.

[Filters](../how-to/filters.md) and [Map domain errors to problem details](../how-to/map-domain-errors-to-problem-details.md)
show steps 3 to 8 in practice.

## A boot that validates everything

The [configuration](../reference/glossary.md#configuration) is loaded first, by `hecate.load_configuration`: it
merges its layers and validates the result against its schema, or raises. `Application:boot()`, which `serve()`
calls, then does the rest of the work that can fail before the first request:

1. Order the feature modules after the modules they require; refuse a duplicate, a cycle or a missing module.
2. Bind the services and validate the container graph: missing bindings and cycles.
3. Collect the controllers and route modules into one route table, and check that every action is a method of its
   controller.
4. Build the dispatcher: compile the router, resolve the schemas of every route, check the binding names that
   controllers declare as dependencies, and compose the filter chain of every route.

Schemas and route declarations are already checked when they are declared, as the modules that hold them load.

Any failure stops the boot with a precise error. Nothing is checked for the first time at the first request: a typo in
a binding name or a path parameter fails when you start the program, not when a client finds it. A failed boot also
changes no process-wide setting.

With several workers, the [primary](../reference/glossary.md#concurrency) boots the application once before it
starts any worker, so such an error is reported once. See
[Multi-process serving](multi-process-serving.md).

## See also

- [The object model](object-model.md)
- [The concurrency model](concurrency-model.md)
- [The HTTP model](http-model.md)
