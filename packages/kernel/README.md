# `hecate-kernel`

> The application: feature modules, controllers, route modules, filters (chain of responsibility), problem details, lifecycle, workers and graceful shutdown.

| | |
|---|---|
| Module | `hecate.kernel` |
| Rock | `hecate-kernel` |
| Layer | 3 — Framework |
| Roadmap phase | 2 |
| Status | in progress: filter chain, results |
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

Further exports (application, controllers, route modules) arrive with later items.

## Layout (once implemented)

```text
src/hecate/kernel/init.lua    public entry point
src/hecate/kernel/chain.lua   filter chain (chain of responsibility)
src/hecate/kernel/results.lua serialisation of results into responses
tests/unit/  tests/integration/  tests/fixtures/
examples/    benchmarks/
```
