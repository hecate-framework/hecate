---
description: Declare routes as data, compile them with hecate.router, match requests with static, parameter and wildcard segments, answer 404 and 405 with Allow, and build URLs from route names.
hecate: "0.x"
lua: "5.5"
order: 13
---

# Route requests

`hecate.router` turns a table of routes into a compiled radix tree and answers one question: which route serves
this method and this path? It does not call the action, validate parameters or build responses; the kernel does that
with the answer.

The router depends only on `hecate.core`. It needs no native module.

## Declare and match

A route is a table with a `method` (or a list of methods), a [path template](../reference/glossary.md#http) in `path`, an optional `name`, and any
metadata you want back. The router keeps the table you gave it; the list of routes is the [route table](../reference/glossary.md#http).

<!-- example: packages/router/examples/hecate.router.Router.lua -->
```lua
-- Declare routes as data, compile them once, match requests and build URLs from route names.
local router = require("hecate.router")

local routes = router.Router({
  { method = "GET", path = "/users", name = "users.list" },
  { method = "GET", path = "/users/{id}", name = "users.show" },
  { method = "DELETE", path = "/users/{id}", name = "users.delete" },
  { method = "GET", path = "/users/me", name = "users.me" },
  { method = "GET", path = "/static/{path...}", name = "static" },
})

local function show(method, path)
  local match = routes:match(method, path)
  if match.status == 200 then
    print(method, path, match.route.name, match.parameters.id or match.parameters.path or "-")
  else
    print(method, path, match.status, match.allow_field or "-")
  end
end

show("GET", "/users/42")
show("GET", "/users/me")
show("DELETE", "/users/me")
show("POST", "/users/42")
show("GET", "/static/css/site.css")
show("GET", "/nothing")
print(routes:url_for("users.show", { id = "Ada Lovelace" }))
-- Prints: GET	/users/42	users.show	42
-- GET	/users/me	users.me	-
-- DELETE	/users/me	users.delete	me
-- POST	/users/42	405	DELETE, GET, HEAD, OPTIONS
-- GET	/static/css/site.css	static	css/site.css
-- GET	/nothing	404	-
-- /users/Ada%20Lovelace
```

`match` always returns a `Match`. Its `status` says what to do:

| Status | Meaning | Other fields |
|---|---|---|
| 200 | a route serves the request | `route`, `parameters` |
| 204 | automatic `OPTIONS` | `allow`, `allow_field` |
| 400 | the path cannot be read | `reason` |
| 404 | no route has this path | none |
| 405 | the path exists, not for this method | `allow`, `allow_field` (the `Allow` field, RFC 9110 section 10.2.1) |

## Path templates

Templates are a subset of RFC 6570 level 1:

- `/users` is a literal path. Literal segments are case-sensitive and may hold percent-encoded bytes.
- `{id}` is a whole segment that binds one non-empty value. `/users/{id}.json` is refused: a parameter is a whole
  segment.
- `{path...}` as the last segment binds the rest of the path (at least one segment) as one string whose `/` separate
  the segments. The notation `...` is the router's own, it is not RFC 6570.

When several routes could serve a path, a static segment wins over a parameter, and a parameter over a wildcard,
segment by segment, going back to a lower-precedence branch when the preferred one has no route for the method.
Matching costs a few table accesses per segment, whatever the number of routes.

## The request path

`http.Request.path` is raw. The router decodes each segment on its own and resolves dot segments, in this order
(RFC 3986 sections 2.1 and 5.2.4):

<!-- example: packages/router/examples/hecate.router.path.lua -->
```lua
-- The router reads the raw path of a request: each segment is decoded on its own and dot segments are resolved first.
local router = require("hecate.router")

local routes = router.Router({
  { method = "GET", path = "/files/{name}", name = "file" },
  { method = "GET", path = "/docs/{topic}/index", name = "index" },
})

-- An encoded slash is data: it does not split the segment.
print(routes:match("GET", "/files/reports%2F2026.pdf").parameters.name)
-- Dot segments never climb above the root and are resolved before matching.
print(routes:match("GET", "/docs/x/../y/./index").parameters.topic)
print(routes:match("GET", "/../../files/a").parameters.name)
-- A path that cannot be read is a 400, not a 404.
local bad = routes:match("GET", "/files/%zz")
print(bad.status, bad.reason)
-- Prints: reports/2026.pdf
-- y
-- a
-- 400	malformed_percent_encoding
```

- `%2F` stays inside its segment. A wildcard refuses a segment whose decoded text holds a `/`, so `..%2F..%2Fsecret`
  never reaches an action as `../../secret`.
- `%2E` is a dot, as RFC 3986 section 6.2.2.2 says. A decoded `.` or `..` is a dot segment; `%252e` is the text `%2e`.
- Empty segments are kept: `/a//b` does not match `/a/{x}/b`.
- A malformed percent sequence and an encoded NUL byte give status 400.

## Trailing slash, HEAD and OPTIONS

By default `/users` and `/users/` are two different paths (`trailing_slash = "strict"`). With
`trailing_slash = "ignore"` they are the same path, and two routes that differ only by the slash are ambiguous. The
router never redirects.

`HEAD` is served by the `GET` route unless you declare a `HEAD` route (`automatic_head = false` turns this off).
`OPTIONS` answers status 204 with `Allow` unless you declare an `OPTIONS` route (`automatic_options = false` turns
this off, and the answer is then 405). The `Allow` of a 405 lists these automatic methods too.

## Mistakes found at boot

`router.Router(routes, options)` compiles once and never changes. It raises `router.RouteTableError`, a
`ConfigurationError`, with a stable `context.reason`, the position of the route (`context.index`) and, for conflicts,
the other route (`context.other_index`):

| Reason | Cause |
|---|---|
| `invalid_route` | not a table, no `method` or `path`, a bad `name` |
| `invalid_method` | not a token, an empty list, a repeated method |
| `invalid_template` | a template the grammar refuses (`context.template_reason` says why) |
| `duplicate_name` | two routes with one name |
| `ambiguous_route` | two routes that serve the same method for the same paths, for example `/users/{id}` and `/users/{user}` |

`/users/me` and `/users/{id}` are not ambiguous: the static route has precedence.

## Reverse routing and introspection

`routes:url_for(name, parameters)` builds the path of a named route. Values are strings or integers and are
percent-encoded; a wildcard value keeps its `/`. It raises `ArgumentError` for an unknown name, a missing or unknown
parameter, and a value no request path could carry (empty, `.`, `..`, a NUL byte). `routes:routes()` lists the
declared routes in order and `routes:route(name)` finds one by name, for OpenAPI generation and documentation.

For the reasons behind the design, see [The HTTP model](../explanation/http-model.md) and the code reference of
[`hecate.router`](../reference/router/index.md).
