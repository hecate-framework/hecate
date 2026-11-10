# `hecate-kernel`

> The application: feature modules, controllers, route modules, filters (chain of responsibility), problem details, lifecycle, workers and graceful shutdown.

| | |
|---|---|
| Module | `hecate.kernel` |
| Rock | `hecate-kernel` |
| Layer | 3 — Framework |
| Roadmap phase | 2 |
| Status | in progress: filter chain, results, problems, route declarations |
| Lua | 5.5 (`lua >= 5.5, < 5.6`) |
| Depends on | [`core`](../core), [`reactor`](../reactor), [`log`](../log), [`http`](../http), [`router`](../router), [`schema`](../schema), [`container`](../container), [`config`](../config), [`json`](../json) |
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
  `kernel.results.is_result(value)` tells whether a value is one.
- `kernel.results.serialisers`: table of media type to serialiser (`fun(plain): string`), default
  `application/json`; `options.serialisers` overrides it per call. Not provided yet: `results.prepare`
  (schemas are already resolved objects, nothing is computed per request beyond `represent` and `encode`).

- `kernel.problems.response(status, detail?)`: an RFC 9457 problem details response (`application/problem+json`, `type`
  `about:blank`, `title`, `status`, `detail`) with a fixed text per status; `detail` is chosen by the caller, never an
  error message. `ArgumentError` for a status outside 400..599.
- `kernel.problems.from_match(match)`: the response for a failed `Router:match` (`404`, `405` with `Allow` per RFC 9110
  section 15.5.6, `400` for an unreadable path without its reason); nil for a match that is not a failure.
- `kernel.problems.from_error(err, options?)`: with `options.input = true`, a `ValidationError` with violations is a
  `422` with `errors`, one `{ pointer, code }` per violation (RFC 6901 pointer, at most `problems.MAX_ERRORS` = 100);
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
tests/unit/  tests/integration/  tests/fixtures/
examples/    benchmarks/
```
