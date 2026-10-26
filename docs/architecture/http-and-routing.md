# HTTP, routing and the kernel

Packages: `http`, `router`, `kernel`. Status: specification.

## `hecate.http`

### Server

- HTTP/1.1 (RFC 9110, RFC 9112) over `hecate.net` streams; TLS optional.
- Parsing via llhttp (OQ-6). Header fields stored case-insensitively with original
  order preserved.
- Persistent connections, pipelining tolerated (responses in order), `Expect:
  100-continue`, chunked transfer coding in both directions.
- Limits, all configurable with safe defaults: request line length, field count and
  size, content length, read and idle deadlines per connection.
- Content is streamed: `request:content()` reads fully (bounded by the limit),
  `request:reader()` streams; responses accept strings, tables (serialised) or
  writer functions.
- Compression (gzip, br) is a later addition.

### Message model

`Request` and `Response` are classes from the shared object model. A request exposes
`method`, `target`, `path`, `query`, `fields` (header fields), parsed `path`
parameters after routing, validated `content`, the `scope`, and the connection's peer
address (`peer_address()`, as on every `net` stream). Responses carry `status`, `fields`, `content`.

### Client

The same package provides an HTTP client (connection reuse per origin, deadlines,
TLS, redirects policy, streaming). It powers the test client's network mode and the
CLI's registry access.

## `hecate.router`

- Compiled **radix tree** per method set; static segments, parameter segments
  (`{id}`) and a trailing wildcard (`{path...}`). Path templates are a subset of
  RFC 6570 level 1.
- Matching cost proportional to path length, independent of the number of routes.
- Ambiguous or conflicting routes are detected at compile time.
- 404 when no path matches; 405 with an `Allow` field when the path matches but the
  method does not; automatic `HEAD` and `OPTIONS` handling (configurable).
- Reverse routing: `router:url_for("users.show", { id = 42 })`.
- Routes are plain data: method(s), path template, name, schemas, metadata, action.

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
first). Typical built-in filters: request identifiers, access logging, CORS, rate
limiting (later), authentication (from `security`).

### Results and serialisation

An action may return:

- a value: serialised as the representation for the declared `200` (or `201` for
  `POST` when declared) response;
- a `Response`: sent as is;
- a problem (`hecate.problem.*`): serialised as `application/problem+json` (RFC 9457).

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
