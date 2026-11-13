# HTTP, routing and the kernel

Packages: `http`, `router`, `kernel`. Status: implemented in Phase 2 (alpha); a statement about something not implemented says so.

## `hecate.http`

### Server

- HTTP/1.1 (RFC 9110, RFC 9112) over `hecate.net` streams; TLS optional.
- Parsing via llhttp (OQ-6). Header fields stored case-insensitively with original
  order preserved.
- Persistent connections, pipelining tolerated (responses in order), `Expect:
  100-continue`, chunked transfer coding in both directions.
- Limits, all configurable with safe defaults: request line length, field count and
  size, content length, read and idle deadlines per connection.
- Content is streamed: `request:read_content()` reads fully (bounded by the limit),
  `request:stream_content()` streams (a `ContentStream`: `read()`, `read_all(limit?)`); responses accept strings or writer functions
  (`http` is bytes only and never serialises, OQ-76 a: the `Response` constructor refuses a table with `ArgumentError`; the kernel serialises).
- Compression (gzip, br) is a later addition.

### Implemented surface

What exists in `hecate.http` (the package README has the full API and the limits table):

- `Request` and `Response` with `Fields`, `MediaType`, `Cookie` and `SetCookie`; a request has `method`, `target`, `path`,
  `query` (both RAW: not percent-decoded, not normalised; the router decodes), `fields`, `peer_address()`, `cookies()`,
  `media_type()`, `read_content()`, `stream_content()`, `read_form()` and `stream_parts()`; its `content` attribute is nil
  for a request from the server (the kernel sets the validated content).
- `Server`: `listen()`, `serve(listener?)`, `shutdown(grace_timeout?)` and `is_stopping()`. `shutdown` closes idle keep-alive connections at once, but gives a fresh
  connection (no byte of its first request head yet) 1 second, or the `grace_timeout` when shorter, to send its request: it
  is then served with `Connection: close`, and closed when none starts. The `host` must be a NUMERIC
  address (default `127.0.0.1`: a name would bind every address it resolves to), with split timeouts (`head_timeout`,
  `idle_timeout`, `content_timeout`, `request_timeout`, `write_timeout`, `drain_timeout`), `max_content`, optional
  `max_connections`, TLS with handshake limits, and an `on_error` and a `logger` option.
- `Client`: a pool per origin, redirects, deadlines, TLS, streaming, `read_json()`.
- `http.problem`, `http.form`, `http.multipart`, `http.url` and the error classes `ParseError`, `ContentError` and `FormError`.
- The answers sent before any action runs (400 malformed, for an HTTP/1.1 request without a `Host`, for any request with more than one `Host` line or an invalid one, for a target with a fragment, and for the asterisk-form outside OPTIONS, RFC 9112 section 3.2; 408, 413, 414, 417, 431, 501 for an
  upgrade) are problem details built by `http.problem` and never reach the kernel.

### Message model

`Request` and `Response` are classes from the shared object model. A request exposes
`method`, `target` (the raw request-target, RFC 9112: `/users/42?expand=orders`), `path` (the
path component of the target as a string: `/users/42`), `fields` (header fields), `parameters`
(the values declared by the route, parsed and validated after routing: `parameters.path`,
`parameters.query`, `parameters.fields`, `parameters.cookies`, the same four keys as the
`parameters` of a route declaration), validated `content`, `scope` (the reactor scope of the request, set by the server), `services` (the service scope of the request, set by the kernel when the application has a container; what a controller's `dependencies` are resolved in), and the connection's peer
address (`peer_address()`, as on every `net` stream). Responses carry `status`, `fields`, `content`.

```lua
-- GET /users/42?expand=orders
function UsersController:show(request)
  local id     = request.parameters.path.id        -- 42, coerced by the route's schema
  local expand = request.parameters.query.expand   -- "orders"
  local where  = request.path                      -- "/users/42"
end
```

### Client

The same package provides an HTTP client (`http.Client`: connection reuse per origin, deadlines,
TLS, redirects policy, streaming; the response content is read with `response:read_content()` or `response:stream_content()`, like the server's request content). It powers the test client's network mode and the
CLI's registry access.

## `hecate.router`

- One compiled **radix tree** over decoded segments, the methods stored per node; static segments, parameter segments
  (`{id}`) and a trailing wildcard (`{path...}`). Path templates are a subset of
  RFC 6570 level 1.
- Matching cost grows with the length of the path. A static segment is one hash lookup, so its cost is independent of
  the number of routes; the parameters with literal text around them (`{id}.json`) at one node are scanned one by one,
  so their cost grows with the number of such siblings; backtracking is bounded by the tree nodes the path reaches.
- Ambiguous or conflicting routes are detected at compile time.
- 404 when no path matches; 405 with an `Allow` field when the path matches but the
  method does not; automatic `HEAD` and `OPTIONS` handling (configurable).
- Reverse routing: `router:url_for("users.show", { id = 42 })`.
- Routes are plain data: method(s), path template, name, schemas, metadata, action.

### Implemented surface

What exists in `hecate.router` (the package README has the API; choices taken are recorded in OQ-83, resolved):

- `Router(routes, options)` compiles a route table once; `match(method, raw_path)` returns a `Match` (200, 204 for the
  automatic `OPTIONS`, 400 for an unreadable path, 404, 405 with a sorted `Allow`); `url_for`, `routes()`, `route(name)`.
- The tree is a radix tree over whole decoded segments: a static child is one hash lookup, so a static step costs the
  same for any number of routes. The affixed siblings of a node (parameters with literal text around them) are scanned
  linearly, and backtracking visits at most the tree nodes the path reaches. Indexing affixed siblings is deferred.
  Precedence is static, parameter with literal text (longest text first), plain parameter, wildcard, with backtracking,
  and a route that does not serve the method is skipped for a lower-precedence one that does. Two affixed siblings of
  the same text length that can match one segment (`a{x}` and `{y}b`) have no precedence between them: two routes
  through them that serve the same method for a common path are `ambiguous_route`.
- The path is read as OQ-75 asks: `http.Request.path` is raw, the router percent-decodes each segment on its own
  (`%2F` is data, RFC 3986 section 2.1) and resolves dot segments first (section 5.2.4; `%2E` is a dot).
- Gaps to RFC 6570 and RFC 3986 are allowed only for security or major performance reasons, and each is documented in
  the guide `how-to/route-requests.md` ("Differences from the standards"); OQ-83 (resolved) records them.
- Ambiguous tables are `RouteTableError` at boot (`ambiguous_route` names both routes), as are invalid templates,
  duplicate names and invalid methods.

## Route declaration

Two styles, one data structure ([ADR 0006](../adr/0006-declarative-routes-as-runtime-data.md)):

1. **Controllers**: classes deriving from `hecate.Controller`, with `prefix`,
   `dependencies`, and `route { ... }` declarations naming an action method.
2. **Route modules**: `hecate.routes(name)` objects with `get`, `post`, ... declarations
   taking an action function.

A route declaration contains: `method`, `path`, `name` (defaults derived), `summary`,
`description`, `tags`, `deprecated`, `parameters` (`path`, `query`, `fields`,
`cookies`), `content` (request schema per media type), `responses` (schema per status
code), `security`, `filters`, and the action. The kernel verifies at boot that every
declared action exists and that path parameters in the template match the declared
`parameters.path`.

In the emitted OpenAPI document, the parameter location `fields` maps to `in: header` (the
OpenAPI term), `path` to `in: path`, `query` to `in: query` and `cookies` to `in: cookie`.

## `hecate.kernel`

### Implemented surface

What exists in `hecate.kernel` (the package [README](../../packages/kernel/README.md) has the full API):

- `Application(options)` boots feature modules, controllers and route modules into one route table and a dispatcher,
  then serves it (`serve`, `shutdown`, `reload`). With a `configuration`, its options are bound to the configuration
  keys (`limits.max_depth`, `errors.expose_details`, `requests.inputs`, `server.*` and the logging keys); an explicit
  option wins. With `workers` above 1 the process is the primary of a `Supervisor` (ADR 0023).
- An action returns a value, a `Response`, a problem, or `respond(status, value?, schema?)` for another status or
  schema.
- Problem classes (`problem.NotFound`, ..., `problem.define` for an application's own) become
  `application/problem+json` responses (RFC 9457). An uncaught error is a `500` without internal details, logged
  through the application's logger or, without one, through `log.default()` on standard error (OQ-79).
- A problem instance may carry header fields (`fields`, OQ-126 (a)): `WWW-Authenticate` for a 401 (RFC 9110,
  sections 11.6.1 and 15.5.2), `Allow` for a 405 (section 15.5.6), `Retry-After` for a 429 or a 503 (section 10.2.3).
  They are copied into the response through `http.Fields`, never into the JSON content nor into the contract of a route
  (`responses`, OpenAPI); an invalid name or value raises `ArgumentError` at construction, and so do the fields the
  kernel owns (`Content-Type`, `Content-Length`, `Transfer-Encoding`, `Connection`). Fields changed after construction
  into an owned one give a logged generic `500`.
- `Accept` is minimal: absent, `*/*`, `application/*` or `application/json` select JSON; anything else is a `406`
  problem. It follows RFC 9110 section 12.5.1: a media type takes the weight of the most specific matching range, and
  `q=0` excludes it (`application/json;q=0, */*` gives 406); equal weights go to the range written first, then JSON.
- Invalid inputs give a `422` whose `errors` entries carry `pointer`, `code` and `source` (`path`, `query`, `header`,
  `cookie` or `content`); `requests.inputs = "strict"` also refuses undeclared query parameters, on every route, including one that
  declares only `content`.
- The binding names of controller `dependencies` are checked against the container at boot
  (`RouteDeclarationError`, `unknown_dependency`), never first at request time.

### Application and feature modules

- `Application` is the composition root: configuration, container, modules, filters,
  servers.
- A **feature module** groups controllers, route modules, services (container bindings),
  migrations and configuration schema for one feature. Modules may declare dependencies
  on other modules; the kernel orders initialisation topologically and rejects cycles.

### Filters (chain of responsibility)

Filters wrap actions. A filter is an object with `handle(request, next)`; it may
short-circuit, transform the request, or post-process the result. Filters are attached
globally, per module, per controller or per route, and execute in that order (outermost
first). The filters of a feature module apply only to the routes of that module; the
global filters apply to every request. Typical built-in filters: request identifiers,
access logging, CORS, rate limiting (later), authentication (from `security`).

The global filters wrap the routing step: the order is the global filters, then the guard
(which turns an error into a problem response), then the route match and the dispatch to
the module, controller and route filters and the action. The global filters therefore also
see the requests that match no route: the `404`, `405` and `400` problem responses and the
automatic `OPTIONS` answer pass through them. At that point `request` carries no route
(`request.parameters.path` is empty, `request.services` is not set yet). An error raised by
the action, or by a filter of an inner layer, becomes a problem response that flows back
through the global filters (their code after `next` runs).

### Results and serialisation

An action may return:

- a value: serialised as the representation for the declared `200` (or `201` for
  `POST` when declared) response;
- a `Response`: sent as is;
- a problem (`hecate.problem.*`): serialised as `application/problem+json` (RFC 9457), with its header
  fields (`fields`) when it has some.

In development and test modes, responses are validated against the declared response
schemas; a mismatch is an error. In production this check is off by default.

### Errors

Uncaught errors become `500` problem details without internal details (unless
development mode). Validation failures become `422` with one entry per violation,
each with a JSON Pointer (RFC 6901) to the offending location.

### Content negotiation

JSON (`application/json`) is the only built-in representation until the `template`
package exists. The negotiation mechanism (`Accept` processing, per-media-type
serialisers) is designed now so that templates plug in later without changes to
controllers.
