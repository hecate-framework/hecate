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
- `{id}` binds one non-empty segment. Literal text may surround the expression inside a segment: `/files/{name}.json`
  binds `name` to `data` for `/files/data.json`, and `v{major}` binds `major` to `2` for `/v2`. A segment holds one
  expression only, so `{a}-{b}` is refused.
- `{path...}` as the last segment binds the rest of the path (at least one segment) as one string whose `/` separate
  the segments. The notation `...` is the router's own, it is not RFC 6570.

When several routes could serve a path, a static segment wins over a parameter with literal text around it
(the longer text first), that over a plain parameter, and a plain parameter over a wildcard, segment by segment, going back to a lower-precedence branch when the preferred one has no route for the method.
Two parameters with literal text of the same length that can match one segment have no precedence between them:
`/f/a{x}` and `/f/{y}b` both match `/f/a1b`, so two such routes for one method are refused at boot
(`ambiguous_route`). `/f/a{x}` and `/f/b{x}` never match the same segment and are accepted.

A static segment costs one table access, whatever the number of routes. The parameters with literal text at one
position are tried one by one, so their cost grows with their number there, and going back to another branch visits
at most the part of the tree the path reaches.

## The request path

`http.Request.path` is raw. The router decodes each segment on its own and resolves dot segments, in this order
(RFC 3986 sections 2.1 and 5.2.4):

<!-- example: packages/router/examples/hecate.router.path.lua -->
```lua
-- The router reads the raw path of a request: each segment is decoded on its
-- own and dot segments are resolved first.
local router = require("hecate.router")

local routes = router.Router({
  { method = "GET", path = "/files/{name}", name = "file" },
  { method = "GET", path = "/docs/{topic}/index", name = "index" },
})

-- An encoded slash is data: it does not split the segment.
print(routes:match("GET", "/files/reports%2F2026.pdf").parameters.name)
-- Prints: reports/2026.pdf

-- Dot segments never climb above the root and are resolved before matching.
print(routes:match("GET", "/docs/x/../y/./index").parameters.topic)
-- Prints: y
print(routes:match("GET", "/../../files/a").parameters.name)
-- Prints: a

-- A path that cannot be read is a 400, not a 404.
local bad = routes:match("GET", "/files/%zz")
print(bad.status, bad.reason)
-- Prints: 400	malformed_percent_encoding
```

- `%2F` stays inside its segment. A wildcard refuses a segment whose decoded text holds a `/`, so `..%2F..%2Fsecret`
  never reaches an action as `../../secret`.
- `%2E` is a dot, as RFC 3986 section 6.2.2.2 says. A decoded `.` or `..` is a dot segment; `%252e` is the text `%2e`.
- Empty segments are kept: `/a//b` does not match `/a/{x}/b`.
- A malformed percent sequence and an encoded NUL byte give status 400.

## Differences from the standards and from common expectations

The router follows RFC 6570 (templates), RFC 3986 (paths) and RFC 9110 (methods, `Allow`). Where it does not, the gap is
listed here with its reason. Only security and major performance reasons justify a gap.

| Gap | What the router does | Reason |
|---|---|---|
| RFC 6570 levels 2 to 4 | Only level 1 expressions: no `{+path}`, `{/path*}`, `{?query}`, no modifiers. | Matching a request back to a template is not defined by RFC 6570, and the query is not part of the route (`schema` validates it). Level 1 is what a radix tree can match without ambiguity. |
| Several expressions in one segment | `{a}-{b}` is refused at boot (`mixed_segment`). | The split of `x-y-z` between `a` and `b` is ambiguous, and a matcher that tries them all costs more than a table access per segment (performance). |
| Wildcard | `{path...}` is the router's own notation, last segment only, one or more non-empty segments. Under `trailing_slash = "strict"` it does not match a path ending with a slash: `/static/a/` ends with an empty segment, which `/static/{path...}` refuses (404 or 405). | RFC 6570 has no notation to match several segments. The notation is not an RFC 6570 expression. An empty segment is refused for the reason of the row "Empty value". |
| Empty value | `{id}` never matches an empty segment: `/a//b` does not match `/a/{x}/b`, and `/files/.json` binds `name` to nothing, so it does not match `/files/{name}.json`. | RFC 6570 allows an empty expansion. An empty identifier is not a value users expect a route to bind, and an empty segment is a classic way to confuse path checks (security). |
| Encoded slash in a wildcard | A wildcard refuses a segment whose decoded text holds `/` (404 or 405). A `{id}` accepts it. | RFC 3986 says `%2F` is data. Accepting it in a wildcard lets `..%2F..%2Fsecret` look like a path a file action then trusts (security, hardening that other frameworks apply to their wildcards too). |
| Unreadable path | A malformed percent sequence or `%00` gives status 400, not 404. | RFC 3986 section 2.1 makes it malformed. NUL truncates strings in C code and filesystems (security). |
| `url_for` values | It refuses an empty value, a NUL byte, and a value that forms the dot segment `.` or `..`. | Matching would never read them back, and a dot segment is resolved away by clients and by this router (security). RFC 6570 expansion accepts them. |
| Invalid UTF-8 | A decoded value is bytes, not checked. | RFC 3986 percent-encodes octets and requires no encoding. Validation belongs to `schema`. |
| Trailing slash | By default `/a` and `/a/` are the same path (`trailing_slash = "ignore"`). RFC 3986 treats them as different URIs; `trailing_slash = "strict"` follows it. | Not a security or performance reason: it is the behaviour users expect of a router, and the owner's choice of default. The strict policy stays one option away. |
| Redirect | The router never redirects, for example from `/a/` to `/a`. | One path, one answer, with no second request. A redirect policy is the application's (`kernel`), not the router's. |

## Trailing slash, HEAD and OPTIONS

By default `/users` and `/users/` are the same path (`trailing_slash = "ignore"`), whichever form the route declares,
and two routes that differ only by the slash are ambiguous. `url_for` keeps the form the route declares. With
`trailing_slash = "strict"` they are two different paths, as RFC 3986 has it. The router never redirects.

`HEAD` is served by the `GET` route unless you declare a `HEAD` route (`automatic_head = false` turns this off).
`OPTIONS` answers status 204 with `Allow` unless you declare an `OPTIONS` route (`automatic_options = false` turns
this off, and the answer is then 405). The `Allow` of a 405 lists these automatic methods too.

## Mistakes found at boot

`router.Router(routes, options)` compiles once and never changes. `routes` is a list with exactly the keys 1..n:
a map or a list with a hole is an `ArgumentError`. It raises `router.RouteTableError`, a
`ConfigurationError`, with a stable `context.reason`, the position of the route (`context.index`) and, for conflicts,
the other route (`context.other_index`):

| Reason | Cause |
|---|---|
| `invalid_route` | not a table, no `method` or `path`, a bad `name` |
| `invalid_method` | not a token, an empty list, a repeated method |
| `invalid_template` | a template the grammar refuses (`context.template_reason` says why) |
| `duplicate_name` | two routes with one name |
| `ambiguous_route` | two routes that serve the same method for the same paths with no precedence between them, for example `/users/{id}` and `/users/{user}`, or `/f/a{x}` and `/f/{y}b` |

`/users/me` and `/users/{id}` are not ambiguous: the static route has precedence.

## Reverse routing and introspection

`routes:url_for(name, parameters)` builds the path of a named route. Values are strings or integers and are
percent-encoded, for a wildcard too; a wildcard string keeps its `/`. It raises `ArgumentError` for an unknown name, a missing or unknown
parameter, and a value no request path could carry (empty, a NUL byte, or a value that makes the segment `.` or `..`). `routes:routes()` lists the
declared routes in order and `routes:route(name)` finds one by name, for OpenAPI generation and documentation.

For the reasons behind the design, see [The HTTP model](../explanation/http-model.md) and the code reference of
[`hecate.router`](../reference/router/index.md).
