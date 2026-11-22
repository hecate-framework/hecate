---
description: What happens to an HTTP request in hecate, from the connection read by the reactor to the response written - filters, routing, validation, the action and serialisation.
hecate: "0.x"
lua: "5.5"
order: 9
---

# The life of a request

This page follows one request through the framework. It is written for hecate 0.x and Lua 5.5. How the packages are layered is explained in [Architecture and layers](../../../../maintainer/en/explanation/architecture-and-layers/), on the maintainer site.

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
