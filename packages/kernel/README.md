# `hecate-kernel`

> The application: feature modules, controllers, route modules, filters (chain of responsibility), problem details, lifecycle, workers and graceful shutdown.

| | |
|---|---|
| Module | `hecate.kernel` |
| Rock | `hecate-kernel` |
| Layer | 3 — Framework |
| Roadmap phase | 2 |
| Status | in progress: filter chain, results, problems, route declarations, dispatcher, validation of the request inputs, `Application` skeleton and feature modules, listening strategies of multi-process serving |
| Lua | 5.5 (`lua >= 5.5, < 5.6`) |
| Depends on | [`core`](../core), [`reactor`](../reactor), [`net`](../net), [`log`](../log), [`http`](../http), [`router`](../router), [`schema`](../schema), [`container`](../container), [`config`](../config), [`json`](../json) |
| Used by | `cli`, `hecate`, `security`, `template`, `test` |
| Native code | none |
| Specification | [http-and-routing.md](../../docs/architecture/http-and-routing.md) |
| Decisions | [ADR 0003](../../docs/adr/0003-transparent-structured-concurrency.md), [ADR 0006](../../docs/adr/0006-declarative-routes-as-runtime-data.md), [ADR 0007](../../docs/adr/0007-object-model.md) |
| Agent | [`pkg-kernel`](../../.claude/agents/pkg-kernel.md) |
| Repository | read-only mirror `hecate-framework/hecate-kernel`, generated from this directory (ADR 0017) |

## Responsibilities

- `Application` (composition root), feature modules, `Controller` superclass, route modules
- boot sequence with full validation (overview.md)
- filters around actions; request scope (the reactor scope of a request) and the scoped lifetime of the container
- coercion/validation of inputs, serialisation of results, response validation in development/test
- problem details mapping of errors
- workers (multi-process) and graceful shutdown
- meta-module `hecate` re-exporting the framework surface

## Non-goals

- templating (later, `template`)

## Standards and references

- RFC 9457 (problem details)
- RFC 9110 (content negotiation)

## Public API

- `kernel.load_configuration(options)`: `hecate.config.load` with `wrap_secret` set to `hecate.log.Secret` unless the options give one, so that the logging sinks render secret values `[redacted]`; pass the result as the `configuration` option of `Application`.
- `kernel.Application(options)`: `boot()` (module order, services, container validation, route table, dispatcher; returns the `serve` function), `serve()` (async, runs an `http.Server`), `shutdown(grace)`, `local_address()` (the address while serving, else nil). Options: `configuration` (binds `limits.max_depth`, `errors.expose_details`, `requests.inputs` and the logging keys, builds and installs the default logger; explicit options win), `modules`, `routes`, `services`, `filters`, `container`, `max_depth`, `expose_details`, `inputs`, `logger`, `router`, `server`, `signals` (only `false`, which disables signal handling for tests and embedding; the signal set is fixed: `sigint` or `sigterm` makes `serve` call `shutdown(grace_timeout)`, and a second one while it drains forces the stop at once, cancelling the requests in flight and logging `shutdown_forced` at `warning`) and `grace_timeout` (seconds, default 30; bound to the configuration key `server.grace_timeout` when a `configuration` is given, an explicit option wins) (default 30 s, OQ-115).
- `kernel.listening` (ADR 0023): `select(name, options?)` returns a new strategy for `auto`, `reuseport` or `round_robin` and, when a named strategy is not supported, the reason of the fallback to `round_robin` (`auto` falls back silently). A strategy has `supported()`, `prepare(endpoint)` (in the primary; `round_robin` binds and returns the address, port 0 allowed; `reuseport` needs a fixed port), `worker_listener(context)` (the listener a worker serves with `http.Server:serve`), `run(workers)` (the dispatch loop of the primary: `round_robin` hands each accepted connection to the next worker of a `WorkerRing` through its `hand_over(stream)`, tries each other worker once when one fails, then closes the connection; `reuseport` returns at once), `close()` and `local_address()`. `WorkerRing` (`add`, `remove`, `size`, `next`, `close`) is the rotation; `HandoffListener` (`push`, `accept`, `close`) is the listener of a `round_robin` worker, fed by its control loop. The supervisor (spawning, readiness, restart, drain) is not built yet.
- Feature module: a table `{ name, requires?, services?, routes?, filters? }`; `kernel.modules.order` sorts it after its requirements. `kernel.ModuleError` carries `context.reason`.

- `kernel.chain.compose(filters, action)`: composes a flat list of filters (outermost first)
  around an action once, at boot, and returns the function that serves a request. One closure
  per filter, none per request; an empty list returns the action itself. An element that is
  not a filter raises `ArgumentError` at composition. Errors of filters propagate unchanged.
  A filter may call `next` more than once; this is not detected.
- `kernel.chain.is_filter(value)`: tells whether a value is a filter (a table with a `handle`
  function).

- `kernel.results.serialise(result, request, route_responses, options?)`: serialises the result of an
  action into a `hecate.http.Response`, a pure function (no socket, no application). A `Response`
  (a problem of `http.problem.response` included) is returned as is; `nil` gives `204` when the route
  declares one, else an empty `200`; a value gives `200` (`201` when `options.created` is true, or for a
  `POST` whose route declares a `201` and no `200`), represented with `route_responses[status]`
  (for example `schema.of(User)`, then `schema:represent`) and encoded; with no schema the value is
  encoded as is, and an instance of a class raises `ArgumentError`. A failure of `represent`
  (`ValidationError`) propagates: the caller maps it to a `500`. No value or message reaches a response.
  `Accept` is minimal: absent, `*/*`, `application/*` or `application/json` select JSON (weights
  honoured, `q=0` excludes), anything else gives a `406` problem details response.
- `kernel.results.respond(status, value?, schema?)`: a tagged result (not a `Response`) that makes
  `serialise` answer with that status, represented with `schema` or the schema the route declares for it.
  `kernel.results.is_result(value)` tells whether a value is one. `kernel.respond` is the same function,
  the short spelling for actions (`return kernel.respond(201, user)`, roadmap kernel item (f)).
- `kernel.results.serialisers`: table of media type to serialiser (`fun(plain): string`), default
  `application/json`; `options.serialisers` overrides it per call. Not provided yet: `results.prepare`
  (schemas are already resolved objects, nothing is computed per request beyond `represent` and `encode`).

- `kernel.problems.response(status, detail?)`: an RFC 9457 problem details response (`application/problem+json`, `type`
  `about:blank`, `title`, `status`, `detail`) with a fixed text per status; `detail` is chosen by the caller, never an
  error message. `ArgumentError` for a status outside 400..599.
- `kernel.problems.from_match(match)`: the response for a failed `Router:match` (`404`, `405` with `Allow` per RFC 9110
  section 15.5.6, `400` for an unreadable path without its reason); nil for a match that is not a failure.
- `kernel.problems.from_error(err, options?)`: with `options.input = true`, a `ValidationError` with violations is a
  `422` with `errors`, one `{ pointer, code }` per violation (RFC 6901 pointer, at most `problems.MAX_ERRORS` = 100), plus
  `source` when the violation carries one (the input step sets it);
  an `http` error keeps its client status; anything else (a `ValidationError` about a response, a Lua error, a value
  that is not an error) is a generic `500`. No message, context or cause of an error ever reaches a response.
- `kernel.problems.guard(action, options?)`: wraps an action or a composed chain; returns the response (a problem for
  an error) and the failure that was caught, logs it at `error` severity when `options.logger` is given, and never
  catches cancellation or deadline errors. Choices: OQ-112.

- `kernel.problem`: problem classes (RFC 9457), built with the object model of `hecate.core`. `Problem` is a subclass of
  `hecate.core.Error`, so an instance is raisable (`error(NotFound { ... })`, mapped by `problems.guard`) and returnable
  by an action (`results.serialise` answers it as `application/problem+json`). Classes: `BadRequest` 400, `Unauthorized`
  401, `Forbidden` 403, `NotFound` 404, `MethodNotAllowed` 405, `Conflict` 409, `Gone` 410, `UnprocessableContent` 422,
  `TooManyRequests` 429, `InternalServerError` 500, `ServiceUnavailable` 503 (the reason phrase is the default title).
  `NotFound { detail = "...", extensions = { ... } }` builds an instance carrying `status`, `title`, `type` (default
  `about:blank`), `detail` (chosen by the developer, never an error message) and `extensions` (RFC 9457, section 3.2;
  `type`, `title`, `status`, `detail` and `instance` are refused with `ArgumentError`, as is any other field). The class
  carries `status`, `title` and `type`, which is what a route's `responses = { [404] = NotFound }` needs.
  `problem.define(name, { status, title, type? })` declares an application's own class (`ArgumentError` unless the status
  is 400..599, the title a non-empty string and `type` a string). `problem.is_problem(value)`, `problem.is_class(value)`.
- `kernel.problems.from_problem(instance)`: the response of a problem instance (no `instance` member). `from_error` and
  `guard` map a raised problem this way; `guard` logs a raised problem only from status 500.
- `options.expose_details` (boolean, default false) of `problems.from_error` and `problems.guard`: when true, each 422
  entry also carries the violation `message` and a generic 500 carries the extension member
  `debug = { error = <class name>, message = <text>, traceback = <when the error has one> }`. When false, nothing of an
  error message or context reaches a response; the `detail` and extensions of a problem are always shown, the developer
  chose them. The kernel will bind this option to the configuration key `errors.expose_details` (OQ-112 (5)); neither
  the key nor the boot warning exists yet (they come with the `config` integration and the `Application`).

- `kernel.routes(name)`: a route module (`kernel.RouteModule`). `module:get(path, spec)` and the curried `module:get "/x" { ... }`
  (same for `post`, `put`, `patch`, `delete`, `head`, `options`) declare a route whose `action` is a function; the
  declaration is validated at once and a mistake leaves the module unchanged. `module:routes()` returns the normalised
  route list, in declaration order.
  `kernel.routes(name, options?)` takes `options = { prefix?, filters? }`, validated at once (`RouteDeclarationError`
  for an unknown field, a non-string or malformed `prefix`, a non-list `filters` or a non-filter element). `prefix` has
  the rule of a controller prefix and is prepended to every route, so the default name `<METHOD> <full path>` includes
  it. `filters` are the DEFAULT filters of each route, not a layer of the chain: a route that declares `filters`
  replaces them, it does not extend them, and an explicit empty list `filters = {}` removes them (a conservative
  choice). The filters of a controller differ: they stay a layer, always before those of the route, never overridable.
  A route module with defaults gives the same entries as the equivalent controller whose routes declare no own filters;
  a route-level override has no controller equivalent.
- `kernel.Controller`: the superclass of controllers; class fields `prefix`, `dependencies` and `filters`.
  `Controller.route(Class, spec)` declares a route whose `action` is the name of a method (validated at once; the
  spelling `Class:route {...}` of developer-experience.md is not possible before finalisation, OQ-113), and
  `Controller.routes(Class)` normalises a finalised class into route entries, refusing an action that is not a method.
  The routes of a class are not inherited.
- `kernel.route.normalise(spec, options)`, `kernel.route.METHODS`, `kernel.route.check_action(entry)`: the single route entry
  (`hecate.kernel.RouteEntry`: `method`, `path`, `name`, `summary`, `description`, `tags`, `deprecated`, `parameters`
  with `path`, `query`, `fields` and `cookies`, `content`, `responses`, `security`, `filters`, `action`, plus `controller`
  and `origin`), usable as a `hecate.router.Route`. The name defaults to `<METHOD> <path>` in both styles, so equivalent
  declarations give equal tables. The parameters of the path template and `parameters.path` must match both ways.
- `kernel.routing.collect(sources)`: the flat route table of route modules and controller classes, ready for
  `router.Router`.
- `kernel.RouteDeclarationError`: a `ConfigurationError`; `context.reason` (`unknown_field`, `invalid_method`, `invalid_path`,
  `parameter_mismatch`, `missing_action`, ...), `context.origin`, `context.field`. Choices: OQ-113.

- `kernel.dispatcher.build(entries, options?)`: the function that serves a request and its router. Per route, once at
  composition, the schemas of the inputs are resolved (`kernel.input.compile(entry, options?)`, returns nil for a route
  that declares no input, which then pays nothing). Inside the chain, after the filters and just before the action:
  `parameters.path`, `query`, `fields` (header fields) and `cookies` are read as texts for the declared names only
  (the query is `application/x-www-form-urlencoded` text read with `http.form`; a repeated key is a list), coerced and
  validated in one `build(raw, { coerce = true })` of an `object` schema, and the result replaces
  `request.parameters.<location>`; the content, when the route declares `application/json`, is read (bounded by the
  limit of the stream), decoded by `json.decode` (nesting ceiling `json.DEFAULT_MAX_DEPTH`), then `build` validates it
  and instantiates class-bound parts (`method = "PATCH"` for a PATCH route); `request.content` holds the result and
  `request:read_content()` and `stream_content()` raise `ContentError` (`consumed`). Failures are problem details
  responses: `422` for violations (every entry carries `source`, one of `path`, `query`, `header` (the `fields`
  location), `cookie` or `content`, and a `pointer` relative to the value inside that source, as in
  `{ "pointer": "/limit", "source": "query", "code": "coercion" }`; `problems.from_error` with `input = true`, so
  nothing of the offending values), `400` for malformed JSON or a bad
  percent-encoding, `413` over the limit, `415` for another `Content-Type`. A route that declares `content` only for
  another media type is refused at build (`RouteDeclarationError`, `unsupported_content_type`). Missing content with no
  `Content-Type` is validated as an absent value (a `default` schema accepts it, otherwise `422`).

- `options.inputs` of `kernel.dispatcher.build` (`"strict"`, the default, or `"lax"`; anything else raises `ArgumentError`):
  the policy for undeclared query parameters (OQ-114 (8)). `lax` drops them. `strict` refuses a request that carries
  one with a `422` whose `errors` has one `{ pointer = "/<name>", source = "query", code = "additional_properties" }`
  per undeclared name (RFC 6901 escaped, in order of appearance, at most `problems.MAX_ERRORS`; the value is never
  echoed; `message` only with `expose_details`). The refusal comes before any coercion, and a route that declares no
  `query` follows the policy too. Undeclared header fields and cookies are always dropped, never refused; the content
  follows its own schema. A request without a query string pays nothing extra. The kernel will bind this option to the
  configuration key `requests.inputs` (default `strict`, `lax` in development and test through the environment files);
  neither the key nor a boot warning exists yet (they come with the `config` integration and the `Application`). Example:
  `GET /users?limit=5&page=2` on a route declaring only `limit` answers `422` with the entry
  `{ "pointer": "/page", "source": "query", "code": "additional_properties" }`.
- `kernel.input.compile(entry, options?)`: `options.strict` (default false) is what the dispatcher sets from `inputs`.

Further exports (application, feature modules) arrive with later items.

## Layout (once implemented)

```text
src/hecate/kernel/init.lua    public entry point
src/hecate/kernel/chain.lua   filter chain (chain of responsibility)
src/hecate/kernel/results.lua serialisation of results into responses
src/hecate/kernel/problem.lua  problem classes (RFC 9457)
src/hecate/kernel/problems.lua mapping of errors to problem details responses
src/hecate/kernel/route.lua    the normalised route entry and its checks
src/hecate/kernel/routes.lua   route modules
src/hecate/kernel/controller.lua  controllers
src/hecate/kernel/routing.lua  the route table of an application
src/hecate/kernel/errors.lua   RouteDeclarationError
src/hecate/kernel/input.lua    validation and coercion of the inputs of a request
src/hecate/kernel/dispatcher.lua  the function that serves a request
tests/unit/  tests/integration/  tests/fixtures/
examples/    benchmarks/
```
