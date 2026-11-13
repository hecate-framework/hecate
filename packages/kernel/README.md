# `hecate-kernel`

> The application: feature modules, controllers, route modules, filters (chain of responsibility), problem details, lifecycle, workers and graceful shutdown.

| | |
|---|---|
| Module | `hecate.kernel` |
| Rock | `hecate-kernel` |
| Layer | 3 — Framework |
| Roadmap phase | 2 |
| Status | alpha — implemented in Phase 2: filter chain, results, problems, route declarations, dispatcher, validation of the request inputs, response validation in development and test, `Application` skeleton and feature modules, listening strategies and supervisor of multi-process serving, wired into `Application` (`workers`, `strategy`), rolling reload of the workers (`Supervisor:reload`, `Application:reload`, `sighup`) |
| Lua | 5.5 (`lua >= 5.5, < 5.6`) |
| Depends on | [`core`](../core), [`reactor`](../reactor), [`net`](../net), [`log`](../log), [`http`](../http), [`router`](../router), [`schema`](../schema), [`container`](../container), [`config`](../config), [`json`](../json) |
| Used by | `cli`, `hecate`, `security`, `template`, `test` |
| Native code | none |
| Specification | [http-and-routing.md](../../docs/architecture/http-and-routing.md) |
| Decisions | [ADR 0003](../../docs/adr/0003-transparent-structured-concurrency.md), [ADR 0006](../../docs/adr/0006-declarative-routes-as-runtime-data.md), [ADR 0007](../../docs/adr/0007-object-model.md), [ADR 0023](../../docs/adr/0023-multi-process-serving.md) (multi-process serving), [ADR 0027](../../docs/adr/0027-kernel-depends-on-net.md) (the kernel depends on `net`); [`concurrency.md`](../../docs/architecture/concurrency.md), "Workers" and "Signals and shutdown". The kernel does not use the ambient context ([ADR 0025](../../docs/adr/0025-ambient-context.md)) yet: binding the request id is deferred (roadmap) |
| Agent | [`pkg-kernel`](../../.claude/agents/pkg-kernel.md) |
| Repository | read-only mirror `hecate-framework/hecate-kernel`, generated from this directory (ADR 0017) |

## Responsibilities

- `Application` (composition root), feature modules, `Controller` superclass, route modules
- boot sequence with full validation (overview.md)
- filters around actions; the service scope of a request (`request.services`, the scoped lifetime of the container)
- coercion/validation of inputs, serialisation of results, response validation in development/test
- problem details mapping of errors
- workers (multi-process): the primary, the supervisor, the listening strategies, the rolling reload
- graceful shutdown on `sigint` and `sigterm`

## Non-goals

- templating (later, `template`)
- the meta-module `hecate`, which re-exports the framework surface (`hecate.respond`, `hecate.problem`, ...): it belongs to the `hecate` package (it re-exports `Application`, `Controller`, `routes`, `respond`, `problem`, `load_configuration` and the kernel errors)
- the command line (`hecate serve --workers`), which belongs to `cli` (Phase 3)

## Standards and references

- RFC 9457 (problem details)
- RFC 9110 (content negotiation)

## Public API

- `kernel.load_configuration(options)`: `hecate.config.load` with `wrap_secret` set to `hecate.log.Secret` unless the options give one, so that the logging sinks render secret values `[redacted]`; pass the result as the `configuration` option of `Application`.
- `kernel.Application(options)`: `boot()` (module order, services, container validation, route table, dispatcher; returns the `action`, the function given to `http.Server`, which serves one request; a failed boot changes no process-wide setting: `max_depth` and the default logger are applied only once everything succeeded, and the only thing left behind is what `services` bound into a container given with the `container` option), `serve()` (async, runs an `http.Server`; once per application: a second call raises `ModuleError` with `reason = "already_served"`; without the native module of `http` it raises `ModuleError` with `reason = "http_unavailable"` and a message naming `lua tools/run.lua build-native http`; a `serve` that fails before the run, such as bad `server` options, does not count and the application can be served again), `shutdown(grace)`, `local_address()` (the address while serving, else nil). Options: `configuration` (binds `limits.max_depth`, `errors.expose_details`, `requests.inputs` and the logging keys, builds and installs the default logger; explicit options win), `modules`, `routes`, `services`, `filters`, `container`, `max_depth`, `expose_details`, `inputs`, `validate_responses` (default from the environment, see below), `logger`, `router`, `server`, `signals` (`true`, the default, or `false`, which disables signal handling for tests and embedding; anything else raises `ArgumentError`; the signal set is fixed: `sigint` or `sigterm` makes `serve` call `shutdown(grace_timeout)`, and a second one while it drains forces the stop at once, cancelling the requests in flight and logging `shutdown_forced` at `warning`) and `grace_timeout` (seconds, default 30; bound to the configuration key `server.grace_timeout` when a `configuration` is given, an explicit option wins) (default 30 s, OQ-115), `workers` (integer at least 1, default 1; key `server.workers`), `strategy` (`auto`, `reuseport` or `round_robin`, default `auto`; key `server.strategy`) and `ready_timeout` (seconds a started or restarted worker may take to report `ready`, default 30; a worker not ready in time is killed, logged `worker_not_ready` at `error` and counted as a crash; used only when `workers` is above 1; no configuration key; a reload has its own `ready_timeout`) `on_crash_loop` (`stop`, the default, or `degrade`; see "Crash loop" below; used only when `workers` is above 1; no configuration key) and `worker_command` (the program and arguments that start a worker; default the running interpreter, main program (`arg[0]`) and arguments, `Application.worker_command_from(arg)`; an interpreter named without a path separator, such as `lua`, is replaced by its absolute path found in `PATH` when there is one, else kept). Workers inherit the whole environment of the primary (including secrets such as `HECATE_*` variables), plus the `HECATE_WORKER_*` variables of their role; a worker validates those: the host is an IP literal or a host name without spaces and the backlog an integer, clamped to 1..65535, otherwise `WorkerRole` raises `ArgumentError`. With `workers = 1` and no worker role the application serves in its own process exactly as before. With `workers` above 1 the process (the primary) boots the application to fail early, then `serve()` runs a `Supervisor` instead of an `http.Server` (logging `workers_starting`, through the default logger when no `logger` option or configuration is given), and `sigint`/`sigterm` stop it with `grace_timeout` (a second signal kills the workers, `Supervisor:force()`); `local_address()` is the primary's socket (`round_robin`) or the configured endpoint (`reuseport`), and nil while an ephemeral port (`port = 0`) is not bound yet. A process started by a supervisor (`supervisor.worker_role()`) boots the application normally and serves through `WorkerRole:serve`; it ignores `sigint`/`sigterm` (the primary sends `stop`). `Application:reload({ grace_timeout?, ready_timeout? })` (async; programmatic, and what `sighup` runs) is `Supervisor:reload` with the logs `reload_started` (`notice`, once the supervisor accepted the reload), `reload_done` (`notice`) and `reload_failed` (`error`, with `reason` and `cause`); a refused reload (`reload_in_progress`, `stopping`, `not_running`) logs `reload_refused` (`warning`) and raises, without `reload_started`; it returns when every worker has been replaced, raises the `SupervisorError` on failure, and raises `ArgumentError` when the application is not serving as a primary of several workers. In a primary `sighup` (watched on every platform but Windows, by the same persistent watcher as `sigint` and `sigterm`) runs the reload in a computation of its own, never crashes the primary, is refused with a `warning` (`reload_refused`) during a reload or a shutdown, and does not start once a shutdown began; in a single process and in a worker it is ignored (`reload_ignored`, `debug`).
- `kernel.listening` (ADR 0023): `select(name, options?)` returns a new strategy for `auto`, `reuseport` or `round_robin` and, when a named strategy is not supported, the reason of the fallback to `round_robin` (`auto` falls back silently). A strategy has `supported()`, `prepare(endpoint)` (in the primary; `round_robin` binds and returns the address, port 0 allowed; `reuseport` needs a fixed port), `worker_listener(context)` (the listener a worker serves with `http.Server:serve`), `run(workers)` (the hand-over loop of the primary: `round_robin` hands each accepted connection over to the next worker of a `WorkerRing` through its `hand_over(stream)`, the hand-over of ADR 0023, tries each other worker once when one fails, then closes the connection; `reuseport` returns at once), `close()` and `local_address()`. `WorkerRing` (`add`, `remove`, `size`, `next`, `close`) is the rotation; `HandOverListener(address?, capacity?)` (`push`, `accept`, `drain`, `close` (returns how many queued connections it closed), `capacity`, `accepted`) is the listener of a `round_robin` worker, fed by its control loop; `HandOverTarget` is what the ring hands connections over to (a worker with `hand_over(stream)`), and the context a worker gives its strategy (`worker_listener`) carries the listener as `hand_over`; it queues at most `capacity` connections (the worker passes its `backlog`, default 128) and `push` closes a connection that does not fit, returning `false, "full"` (the worker logs `hand_over_queue_full` at `warning`; the primary is not told). A worker logs `hand_over_discarded` (`warning`, `count`) for the connections still queued when it stops, and `control_failed` (`error`, `reason`) when its message pipe to the primary breaks.
- `kernel.supervisor` (ADR 0023): `Supervisor({ command, count, endpoint, strategy?, env?, logger?, restart_delay?, crash_limit?, crash_window?, on_crash_loop?, ready_timeout? })` in the primary: `run()` prepares the strategy, starts `count` workers (`reactor.spawn` of `command` with a message pipe and the `HECATE_WORKER_*` variables), adds each to the rotation once it sends `ready`, restarts a worker that exits after `restart_delay` (default 0.1 s, doubled per crash within the window, at most 10 s), and raises `SupervisorError` (`crash_loop`) after `crash_limit` exits (default 5) within `crash_window` (default 60 s); `stop(grace_timeout?)` sends `stop <seconds>` to every worker and kills those still running one second after the grace period; `local_address()` (nil before `run`, and while an ephemeral port is not bound), `ready_count()`, `started_count()`, `counters()`. A worker that does not send `ready` within `ready_timeout` seconds (default 30) of its start, first start or restart, is killed, logged `worker_not_ready` at `error` and counted as a crash (backoff and crash limit apply); a reload has its own `ready_timeout`. Counters: the worker role sends `counters <requests> <connections>` over the message pipe at most once per second, only when a value changed, and once more when it has stopped serving (two non-negative decimal integers; `requests` is `-` when unknown, which is always the case today because `http.Server` has no request counter; `connections` is the number of connections the hand-over listener accepted, so a `reuseport` worker, whose listener keeps no counter, sends nothing); the primary keeps the latest values of each worker and ignores a malformed message; `Supervisor:counters()` returns `{ worker, pid, connections, requests }` entries (`requests` nil when unknown) for the workers in service that reported, and a restarted worker has none until it reports. When a worker that reported exits having accepted fewer connections than the primary handed over to it, the primary logs `hand_over_unaccounted` at `warning` (`worker`, `pid`, `handed`, `accepted`). The reporter is a computation of its own: it never delays the handling of `stop`. Hand-over: the primary writes each `connection` frame with `keep_open` and holds the stream in a FIFO per worker process until the worker answers `received` (one per frame that carried a stream, whether it queued or refused it; written by a computation of its own, so `stop` is never delayed); when the worker's message pipe ends or the worker exits or is killed, the primary closes every stream still held for it, and it ignores a `received` with nothing held. The streams held for a worker are bounded by the connections in flight to it (OQ-118: a stream in flight in a message pipe is held by no process, and macOS discards it). In a worker, `supervisor.worker_role()` returns a `WorkerRole` (nil elsewhere): `listener()`, `control(on_stop, default_grace)` and `serve(server, default_grace?)`, which tells the primary it is ready, serves, and drains on `stop` or when the message pipe closes (the primary died). `kernel.SupervisorError` (`crash_loop`, `start_failed`, `already_run`, `reload_failed`, `reload_in_progress`, `stopping`, `not_running`). `Supervisor:force()` kills the running workers at once (the second signal). `Application` starts the supervisor and the worker role itself (see `kernel.Application`). `Supervisor:reload({ grace_timeout?, ready_timeout?, on_accepted? })` (async; `on_accepted` is called once when the reload is accepted, before the first replacement, never for a refused one) is the rolling reload (Decision 6): for each slot, one at a time, it starts a fresh process from the same command (so it runs the code on disk now), waits for its `ready` (`ready_timeout`, default 30 s), puts it in the rotation, then takes the old worker out of the rotation and stops it with `stop <grace_timeout>` (killed one second after the grace period, as by `stop`); the old worker is never taken out first, so a replacement that exits, cannot start or is not ready in time aborts the reload with `SupervisorError` (`reload_failed`, `context.cause` `start_failed`, `exited`, `not_ready`, `worker_lost` or `stopping`, `context.worker`) and leaves the old worker in service (slots already replaced stay replaced). The planned exit of the old worker is not a crash (no restart, nothing counted towards `crash_limit`); the number of workers is unchanged. A second reload raises `reload_in_progress`, a reload during or after a stop raises `stopping` or `not_running`, and a `stop` during a reload ends it (`reload_failed`, cause `stopping`). The reload is replace-by-restart: it sends no message of its own, the `reload` message stays reserved in the protocol and unused. With `reuseport` the connections queued in the socket of the closing worker are reset by the kernel (ADR 0023 Decision 6, the stated limit of that strategy).
- Feature module: a table `{ name, requires?, services?, routes?, filters? }`; `kernel.modules.order` sorts it after its requirements. Its `filters` apply only to the routes of that module (layers: global, module, controller, route). `kernel.ModuleError` carries `context.reason`.
- Global filters (the `filters` option of `Application`) wrap the routing step: order global filters, guard (`problems.guard`), match and dispatch. They also see the 404, 405, 400 and automatic `OPTIONS` answers; for those `request` carries no route (`request.parameters.path` is empty, `request.services` is not set). An error of the action becomes a problem response that flows back through them.

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
  an error) and the failure that was caught, logs it at `error` severity when `options.logger` is given (fields `error`, `method`, `path`
  without the query, and `traceback`, taken where the error was raised), and never
  catches cancellation or deadline errors. Choices: OQ-112.

- `kernel.problem`: problem classes (RFC 9457), built with the object model of `hecate.core`. `Problem` is a subclass of
  `hecate.core.Error`, so an instance is raisable (`error(NotFound { ... })`, mapped by `problems.guard`) and returnable
  by an action (`results.serialise` answers it as `application/problem+json`). Classes: `BadRequest` 400, `Unauthorized`
  401, `Forbidden` 403, `NotFound` 404, `MethodNotAllowed` 405, `NotAcceptable` 406, `RequestTimeout` 408, `Conflict` 409,
  `Gone` 410, `PreconditionFailed` 412, `ContentTooLarge` 413, `UnsupportedMediaType` 415, `UnprocessableContent` 422,
  `TooManyRequests` 429, `InternalServerError` 500, `BadGateway` 502, `ServiceUnavailable` 503, `GatewayTimeout` 504
  (the reason phrase is the default title). Every class has a `code` of the shape `<namespace>.problem.<Name>`:
  `hecate.problem.NotFound` for a built-in class, `app.problem.<Name>` for a class of `problem.define`.
  `NotFound { detail = "...", extensions = { ... } }` builds an instance carrying `status`, `title`, `type` (default
  `about:blank`), `detail` (chosen by the developer, never an error message) and `extensions` (RFC 9457, section 3.2;
  `type`, `title`, `status`, `detail` and `instance` are refused with `ArgumentError`, as is any other field). The class
  carries `status`, `title` and `type`, which is what a route's `responses = { [404] = NotFound }` needs.
  `problem.define(name, { status, title, type?, code? })` declares an application's own class; its `code` is
  `app.problem.<name>` unless `code` gives another one, and a code in the `hecate.` namespace, which belongs to the framework,
  is refused (`ArgumentError` also unless the status is 400..599, the title a non-empty string and `type` a string). `problem.is_problem(value)`, `problem.is_class(value)`.
- `kernel.problems.from_problem(instance)`: the response of a problem instance (no `instance` member). `from_error` and
  `guard` map a raised problem this way; `guard` logs a raised problem only from status 500.
- `options.expose_details` (boolean, default false) of `problems.from_error` and `problems.guard`: when true, each 422
  entry also carries the violation `message` and a generic 500 carries the extension member
  `debug = { error = <class name>, message = <text>, traceback = <when the error has one> }`. When false, nothing of an
  error message or context reaches a response; the `detail` and extensions of a problem are always shown, the developer
  chose them. `Application` binds this option to the configuration key `errors.expose_details` (OQ-112 (5)) and logs the
  boot warning `expose_details_in_production` (`warning`) when it is true in the environment `production`.

- `kernel.routes(name)`: a route module (`kernel.RouteModule`). `module:get(path, spec)` and the curried `module:get "/x" { ... }`
  (same for `post`, `put`, `patch`, `delete`, `head`, `options`) declare a route whose `action` is a function; the
  declaration is validated at once and a mistake leaves the module unchanged. `module:routes()` returns the normalised
  route list, in declaration order; it raises `RouteDeclarationError` (`incomplete_route`) when a verb was called
  without its table of declarations (`module:get "/x"` alone), which would otherwise drop the route silently.
  `kernel.routes(name, options?)` takes `options = { prefix?, filters? }`, validated at once (`RouteDeclarationError`
  for an unknown field, a non-string or malformed `prefix`, a non-list `filters` or a non-filter element). `prefix` has
  the rule of a controller prefix and is prepended to every route, so the default name `<METHOD> <full path>` includes
  it. `filters` are the DEFAULT filters of each route, not a layer of the chain: a route that declares `filters`
  replaces them, it does not extend them, and an explicit empty list `filters = {}` removes them (a conservative
  choice). The filters of a controller differ: they stay a layer, always before those of the route, never overridable.
  A route module with defaults gives the same entries as the equivalent controller whose routes declare no own filters;
  a route-level override has no controller equivalent.
- `kernel.Controller`: the superclass of controllers; class fields `prefix`, `dependencies`, `filters` and `routes`.
  `Controller.route(Class, spec)` declares a route whose `action` is the name of a method (validated at once; it keeps a
  copy of `spec`, so later changes to the table have no effect; the spelling `Class:route {...}` of
  developer-experience.md is not possible before finalisation, OQ-113), and `Controller.entries(Class)` normalises a
  finalised class into route entries (the declarations of `Controller.route`, then those of the class field `routes`),
  refusing an action that is not a method. The routes of a class are not inherited, and neither is its `prefix`: a
  subclass that sets none has none, whatever its superclass declares (the class field is read from the class itself,
  not from the copy of the members a finalised class carries). The `dependencies` of a controller (field name to
  binding name) are resolved in `request.services` in the sorted order of the field names, one new instance per request.
- `kernel.route.normalise(spec, options)`, `kernel.route.METHODS`, `kernel.route.check_action(entry)`: the single route entry
  (`hecate.kernel.RouteEntry`: `method`, `path`, `name`, `summary`, `description`, `tags`, `deprecated`, `parameters`
  with `path`, `query`, `fields` and `cookies`, `content`, `responses`, `security`, `filters`, `action`, plus `controller`
  and `origin`), usable as a `hecate.router.Route`. A `responses` value is a schema, a problem class or `true`, which
  declares a status without content (`[204] = true`). The name defaults to `<METHOD> <path>` in both styles, so equivalent
  declarations give equal tables. The parameters of the path template and `parameters.path` must match both ways.
- `kernel.routing.collect(sources, module_filters?)`: the flat route table of route modules and controller classes, ready for
  `router.Router`. With `module_filters`, each entry is a copy tagged `module_filters` (the second layer of its chain).
- `kernel.RouteDeclarationError`: a `ConfigurationError`, the one error of a route declaration, at declaration or at boot:
  a type mistake in an argument of `kernel.routes`, a verb or `Controller.route` is `reason = "invalid_argument"`.
  `context.reason` (`invalid_argument`, `invalid_options`, `unknown_field`, `invalid_method`, `invalid_path`, `invalid_name`,
  `invalid_text`, `invalid_tags`, `invalid_deprecated`, `invalid_parameters`, `parameter_mismatch`, `invalid_content`,
  `invalid_responses`, `invalid_security`, `invalid_filters`, `invalid_action`, `missing_action`, `invalid_controller`,
  `invalid_routes`, `invalid_source`, `incomplete_route`, `missing_container`, `unsupported_content_type`; the list is
  on the class), `context.origin`, `context.field`. Choices: OQ-113.
- Errors of the kernel (`RouteDeclarationError`, `ModuleError`, `SupervisorError`): `code` is the code of the class and the
  reason, `hecate.kernel.RouteDeclarationError.invalid_path`, and `context.reason` stays (the error without a reason keeps
  the code of its class). Every message starts with `hecate.kernel.<module>.<function>:`, says what it got
  (`got string "get"`, `got nil`) and, for a closed set, the valid choices (`unknown option 'x' (valid: ...)`).
- `hecate.kernel.Request` (annotation class, extends `hecate.http.Request`): the request seen by filters and actions.
  The kernel adds `services` (the service scope of the request, `request.services:resolve("name")`; `request.scope`
  stays the reactor scope that `http.Server` sets), `parameters.path`, `parameters.query`, `parameters.fields` and
  `parameters.cookies` (the declared values, coerced and validated just before the action) and `content` (the validated
  content).

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
  follows its own schema. A request without a query string pays nothing extra. `Application` binds this option to the
  configuration key `requests.inputs` (default `strict`, `lax` in development and test through the environment files;
  an explicit `inputs` option wins). Example:
  `GET /users?limit=5&page=2` on a route declaring only `limit` answers `422` with the entry
  `{ "pointer": "/page", "source": "query", "code": "additional_properties" }`.
- `kernel.input.compile(entry, options?)`: `options.strict` (default false) is what the dispatcher sets from `inputs`.
- Response validation in development and test (http-and-routing.md, "Results and serialisation"): `options.validate_responses`
  of `kernel.dispatcher.build` and of `results.serialise` (boolean, default false; anything else raises `ArgumentError` in the
  dispatcher). When true, the representation of a result that has a schema declared for its status (or given to `respond`)
  is validated with `schema:validate`; a mismatch raises `hecate.core.ValidationError` (`context.status`,
  `context.violations`; the message names the status and the code of the first violation, never a value and never the pointer into the data),
  which the guard turns into a logged `500` (`debug` only with `expose_details`). A `Response`, a problem and a value
  without schema are not checked. `Application` option `validate_responses`; with a `configuration` and no explicit
  option it is true in the environments `development` and `test`, false otherwise, and false without a configuration
  (OQ-117). Example: a route declaring `responses = { [200] = schema.object({ id = schema.integer() }) }` whose action
  returns `{ id = "x" }` answers `500` in development and `200` with `{"id":"x"}` in production.

- **Crash loop** (`Supervisor` option and `Application` option `on_crash_loop`, `"stop"` default or `"degrade"`): with
  `"stop"` workers that keep exiting (`crash_limit` within `crash_window`) end `run` with a `SupervisorError`
  (`crash_loop`); with `"degrade"` the supervisor keeps restarting at the maximum backoff (10 s), logs `crash_loop` at
  `error` once per window and never ends `run` by itself. A configuration key `server.on_crash_loop` is a candidate,
  not decided: only the options exist for now.
- **Problem extensions** that cannot be encoded (a cycle, a value nested too deep) answer the generic `500` and are logged
  at `error` with the code of the problem, never the value; a function or a non-finite number is refused at construction.

- `hecate.kernel.logging` (module, not a field of `kernel`): `build(configuration)` builds the default logger of an
  `Application` from the `logging.*` keys (severity, named severities, sinks, `async`, `redact` added to
  `log.DEFAULT_REDACT`); it raises `ArgumentError` for a `file` sink without a path.
- `hecate.kernel.Filter` (annotation class) and `hecate.kernel.Action` (annotation alias): a filter is any table with a
  `handle(request, next)` function, an action is `fun(request): ...any`. Both are duck-typed;
  `kernel.chain.is_filter` tells a filter.

## Limits

- **Windows and signals.** Windows never delivers `sigterm` and the kernel does not watch `sighup` there. A service
  manager that stops the primary with `TerminateProcess` gets no graceful shutdown. The workers notice that the message
  pipe closed and drain with the default grace period. `sigint` (Ctrl+C) works.
- **`reuseport` on Linux.** `SO_REUSEPORT` lets any process of the same user bind the same port and take a share of the
  connections. On a shared host, `round_robin` is the safer choice.
- **A worker swallows `sigterm` and `sigint`.** `kill <worker pid>` does nothing; only the primary stops a worker (the
  `stop` message). A terminal sends its signals to the whole process group, hence this choice.
- **`json.set_max_depth` is process-global.** Two `Application`s in one process share the limit.
- **`results.serialisers` is a process-wide table.** Every application of the process shares the serialisers of a
  media type.
- **Global filters and `request.services`.** The service scope is opened after routing, so a global filter cannot use
  `request.services`. Use a module, controller or route filter.

## Layout

```text
src/hecate/kernel/init.lua    public entry point
src/hecate/kernel/application.lua  Application, the composition root, and the signals
src/hecate/kernel/modules.lua  validation and ordering of feature modules
src/hecate/kernel/logging.lua  the default logger built from the logging keys
src/hecate/kernel/listening.lua  listening strategies, WorkerRing, HandOverListener
src/hecate/kernel/supervisor.lua  Supervisor (primary), WorkerRole (worker), rolling reload
src/hecate/kernel/chain.lua   filter chain (chain of responsibility)
src/hecate/kernel/results.lua serialisation of results into responses
src/hecate/kernel/problem.lua  problem classes (RFC 9457)
src/hecate/kernel/problems.lua mapping of errors to problem details responses
src/hecate/kernel/route.lua    the normalised route entry and its checks
src/hecate/kernel/routes.lua   route modules
src/hecate/kernel/controller.lua  controllers
src/hecate/kernel/routing.lua  the route table of an application
src/hecate/kernel/errors.lua   RouteDeclarationError, ModuleError, SupervisorError
src/hecate/kernel/input.lua    validation and coercion of the inputs of a request
src/hecate/kernel/dispatcher.lua  the function that serves a request
tests/unit/  tests/integration/  tests/fixtures/  tests/helpers/
```

Benchmark: the repository scenario `benchmarks/scenarios/kernel-json`. Tested example: `examples/hello`.
