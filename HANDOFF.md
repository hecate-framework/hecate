<!-- Relay handoff note. Lives only on relay branches; deleted before review. -->
# Handoff

- roadmap_item: `kernel`: application, modules, controllers, route modules, filters, problem details, lifecycle, multi-process workers, graceful shutdown (Phase 2, docs/roadmap.md)
- status: in-progress
- lock_until: 2026-11-10T18:48:31Z
- last_update: 2026-11-10T18:48:31Z

## Done

- Claimed the item (previous relay branch was already merged into main via PR #162/#165); draft PR #166 opened (labels relay, package:kernel, package:http).
- Step 1: split http `server.lua`/`client.lua` into `internal/` modules, no API change (typecheck and `test http` ok; macOS/Windows CI and benchmarks pending).

- CI of PR #166 green on the three platforms at 69069b1.
- Step 2a: `log.default()` / `log.set_default()` (OQ-79), tests in `packages/log/tests/unit/default_logger_test.lua`.
- Step 3 (owner request): split `schema/schema.lua` (2081 to 109 lines) into `internal/` modules, no API change; typecheck, lint and `test schema` ok. `validation.lua` (1164 lines) stays large on purpose: shared upvalue state on the hot path. Benchmark `validate.lua` class-bound `BenchPerson` scenario fails (reported as also failing before the split; not verified by me). `test doc` needs the native module (no Rust here).
- Step 4: `http.serve_request` (OQ-78), writer split into pure `normalise` + write, JSON fallback removed (OQ-76 a), `log.default()` used by the server when no `logger` is given (OQ-79). Tests in `packages/http/tests/unit/dispatch_test.lua` and `server_lifecycle_test.lua`; typecheck, lint, `test http`, `test log` ok. No writer benchmark exists here (only `http/parse`, `http/forms`, `tcp-echo`, `accept-spread`).
- Step 5a: `on_response` hook (OQ-81) in `server_response.lua`, tests in `server_lifecycle_test.lua`; typecheck, lint, `test http` ok (needs `build-native http json`). Website reference page for the option not yet updated.
- CI green at 26e4200. Step 5b: `json.set_max_depth` (OQ-101 a), `schema` reads `json.DEFAULT_MAX_DEPTH`; tests in `packages/json/tests/unit/max_depth_test.lua` and `deep_test.lua`; typecheck, lint, `test json`, `test schema` ok.
- Step 6 (owner decisions of 2026-11-09): `dispatch` renamed `http.serve_request`; `Response` content narrowed to `string|function|nil` (the constructor refuses a table); `log.DEFAULT_REDACT` (19 names) used by `log.default()`; OQ-111 recorded (issue #167 closed); *safe content* added as check 4 of every phase gate (roadmap, relay.md, ai-assisted-development.md); a "Before going to production" page added to the roadmap. Lock released (`lock_until` = last update).
- Step 7 (run of 21:05Z, lock released at the end): `hecate.kernel.chain.compose(filters, action)` and `chain.is_filter`, first code of `packages/kernel`; 15 tests; typecheck, lint, `test kernel` ok. Doubt: `next` called twice is not detected (it would cost an allocation per filter per request; a retry filter is legitimate); recorded as documented behaviour.
- Step 8 (run of ~21:11Z, lock released at the end): `hecate.kernel.results` (`serialise`, `respond`, `serialisers`, minimal `Accept` negotiation with 406); 17 tests; typecheck, lint, `test kernel` ok. Choices to confirm: plain value is 200 (201 with `created = true`, or POST with only a 201 declared); a nil result is 204 if the route declares it, else an empty 200. Not done: validation of the result against the schema in development/test (later item).
- Step 9 (run of ~21:50Z, lock released): `hecate.kernel.problems` (`response`, `from_match`, `from_error`, `guard`), 19 tests, OQ-112 (choices to confirm; mirror issue created by the relay); typecheck, lint, `test kernel` ok. `http.serve_request` already catches errors: the Application decides which layer owns the mapping (`guard` sits just inside it).

- Owner decisions on OQ-112 (2026-11-09, recorded in `docs/open-questions.md`, resolved; issue #168 closed): `errors.expose_details`, `hecate.problem.*` classes (returnable and raisable, `define`), messages in 422 entries when exposed. Roadmap kernel item (h) and (i).
- Step 9 (run of ~22:10Z, lock released at the end): `hecate.kernel.problem` (`Problem` subclass of `core.Error`, 11 status classes, `define`, `is_problem`, `is_class`), `problems.from_problem`, `options.expose_details` (422 entries carry `message`, a generic 500 carries `debug`); 19 tests; typecheck, lint, `test kernel` ok. Choices to confirm: `guard` does not log a raised Problem below 500; `Problem.init` accepts only `detail` and `extensions`. Left for the handoffs: the config key `errors.expose_details` and the boot warning, OpenAPI components for problem classes, the `hecate.problem` re-export.

- Step 10 (run of 2026-11-10T00:48:38Z, lock released at the end): route declaration layer in `hecate.kernel`: `routes(name)` route modules, `Controller` (`Controller.route(Class, spec)`), normalised entry `route.normalise`, `routing.collect`, `RouteDeclarationError`; 21 tests; typecheck, lint, `test kernel`, check-boundaries, check-glossary ok. Choices to confirm: OQ-113 (notably `Controller:route{}` spelling impossible before finalisation, default route name `<METHOD> <path>`).

- CI fix (run of 2026-11-10T03:50Z, lock released at the end): CI of 085f685 failed on the three platforms at `check-annotations` (`Problem.code` had no `---@field`); added the field. `check-annotations`, typecheck ok; `test kernel` here fails only for the unbuilt json native module (no Rust). Remember to run `check-annotations` before pushing.

- Step 11 (run of 2026-11-10T06:45:20Z, lock released at the end): `hecate.kernel.dispatcher.build(entries, options)` returns `serve(request)` and the router: match (404/405/400, automatic OPTIONS 204), service scope per request, controller instance per request with `dependencies` resolved in `request.scope`, global then entry filters composed once, `results.serialise`, `problems.guard`; 6 tests; typecheck, lint, check-annotations, check-boundaries, `test kernel` ok (json native built with `build-native json http`). Path parameters are given as raw decoded strings: coercion/validation by route schemas not done yet.

- Step 12 (run of ~08:00Z, lock released at the end): `hecate.kernel.input` (parameters path/query/fields/cookies and JSON content validated and coerced by the route schemas, wired into the dispatcher), `Request:set_validated_content` in `http` (reading consumed content raises `ContentError` `consumed`, mapped to a 500), 14 tests; typecheck, lint, check-annotations, `test kernel`, `test http` ok. Choices to confirm: OQ-114.

- OQ-113 resolved by the owner (2026-11-10, in `docs/open-questions.md`, issue #169 closed): both `Controller.route` and the class field `routes`, route names free (default `<METHOD> <path>`), strict parameters without shorthand, route-module options `{ prefix, filters }` with per-route default filters replaced by a route's own. Roadmap kernel items (j) and (k).
- Step 14 (run of ~10:00Z, lock released at the end): roadmap kernel item (k) done: `hecate.routes(name, { prefix, filters })`, filters are per-route defaults replaced by a route's own (an empty list removes them), controller filters unchanged; 8 new tests; a prefix of a single `/` is now refused (it gave `//x`, also for controllers). typecheck, lint, check-annotations, `test kernel` ok. Choice to confirm (in OQ-113 (8)): `filters = {}` on a route removes the defaults.

- Step 13 (run of 2026-11-10T09:43Z, lock released at the end): roadmap kernel item (j) done: class field `routes = {...}` read by `Controller.routes` after `Controller.route` declarations (inherited copies ignored, non-table refused with `invalid_routes`); 2 tests; typecheck, lint, check-annotations, `test kernel` ok. CI of 94b22de was green on the three platforms.

- OQ-114 resolved by the owner (2026-11-10, issue #170 closed): `source` member and relative pointers in 422 entries, `schema.optional` bug, `lax`/`strict` policy for undeclared query parameters (config key `requests.inputs`, roadmap kernel item (l)), per-route `max_content` deferred as a known limitation.
- Step 15 (run of ~10:10Z, lock released at the end): kernel: 422 entries carry `source` with a relative pointer, dispatcher option `inputs` (`strict` default, `lax`) for undeclared query parameters (OQ-114 (1), (8)); schema: a top-level `optional` accepts an absent value (OQ-114 (5), root cause: only `object` knew how to skip an absent property), with a kernel regression test. typecheck, lint, check-annotations, `test kernel`, `test schema` ok. Handoff (l): declare the config key `requests.inputs` and bind it to `inputs`. Choices to confirm: in strict mode an undeclared name is refused before coercion (a request with both gets only the undeclared entries); a malformed query is a 400 in both modes.

- Step 16 (run of 2026-11-10T12:41Z, lock released at the end): `kernel.Application` skeleton (`boot`, `serve`, `shutdown`), `kernel.modules.order`, `ModuleError`; 5 tests; typecheck, lint, check-annotations, check-boundaries, check-glossary, `test kernel` ok. Not yet done: graceful shutdown on signals, config binding, `hecate.respond`, response validation, website reference page.

- Step 17 (run of 2026-11-10T15:40Z, lock released at the end): `config` declares `errors.expose_details` and `requests.inputs` (names reserved); `kernel.Application` option `configuration` binds them, `limits.max_depth` and the logging keys (`kernel.logging.build`, default logger installed with `log.set_default`), boot warning for `expose_details` in production; 5 tests; typecheck, lint, check-annotations, check-boundaries, check-glossary, `test kernel`, `test config` ok. Roadmap handoffs (a), (b), (h), (l) done in code; `wrap_secret` (c) not yet wired (`config.load` is called by the user, not the kernel). Doc of the generated `config/development.lua` left to the `cli` item.

- Step 18 (run of 2026-11-10T18:41Z, lock released at the end): `Application:serve` watches `sigint`/`sigterm` (options `signals`, list or `false`, and `grace_timeout`, default 30) and calls `shutdown`; the signal is logged (`shutdown_signal`), an unwatchable one is a warning (`signals_unavailable`); 3 tests (signal test POSIX only, with `sigusr2`); typecheck, lint, check-annotations, check-boundaries, check-glossary, check-changelog, check-links, `test kernel` ok (after `build-native json`, `build-native http`). Choices to confirm: OQ-115 (issue #171).

## Next steps

0. Kernel code still open: multi-process workers (ADR 0023: primary, `round_robin`, supervision, drain per worker; `SIGHUP` reload, OQ-115 (4)), a `kernel.respond` re-export of `results.respond` for (f), response validation in development/test, `wrap_secret = log.Secret` (c) where the kernel loads the configuration, the website reference page of `kernel`. Check CI of the pull request first.
1. Before ticking: verify handoffs (a), (b), (d), (e), (g), (h), (i), (j), (k), (l) against the roadmap text (most are done in code, see Done), then `/review-package kernel`.

## Decisions taken (and where they are recorded)

- Worked on the session-designated branch `claude/sweet-feynman-h1j6tu` instead of `claude/relay-kernel` (session instruction).

## Doubts and questions for the owner

- Should a filter calling `next` twice be detected (error naming the filter)? The chain does not detect it today (no per-request allocation); a formal `Filter` interface in `core` terms is also undecided (duck-typed `handle` for now).

- `dispatch` was renamed `serve_request` (owner decision, uses the glossary verb "serve" of the term action): update the glossary row and OQ-78 text if needed.
- The server logs `tostring(failure)` of an unhandled action error (free text, not redacted by design, OQ-111); the production checklist page and the *safe content* gate check cover it.
- `Response(200, { content = table })` is still accepted by the `Response` constructor (only the server and `dispatch` refuse it); the kernel step decides whether to narrow it.

- The run was triggered by a bare "Retry" message with no task text; I assumed the relay routine and started the first unchecked roadmap item.

## Commands to re-run

```sh
eval "$(luarocks path)"        # luv is only found after this (tools/cloud/README.md)
lua tools/run.lua setup-luals   # once per session: pinned LuaLS into spikes/luals
lua tools/run.lua typecheck     # required before every push (CI fails on any warning)
```
