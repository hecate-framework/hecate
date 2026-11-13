# Phase 2 gate report

Date: 2026-11-13. Pass at the head of `claude/relay-phase-2-gate` (pull request 183), which holds `main` eb9d9b7
(merge of pull request 182) plus the fixes listed below, on Linux (Ubuntu 24.04 x86_64, Lua 5.5, GCC 13, cargo).
Windows is not a benchmark target.

Scope: completeness (section 1), it works (section 2), coherence (section 3), safe content (section 4, OQ-111),
open questions (section 5), and the findings with their disposition (section 6).

## 1. Completeness

| Roadmap item | Evidence |
|---|---|
| `http` | `packages/http/src` (server split into `internal/server_{options,response,connection}.lua`, client into `internal/client_{pool,redirect,connection,exchange}.lua`); unit, integration, RFC 9112 conformance and smuggling tests; benchmarks `parse` and `forms`; README alpha; how-tos `serve-http`, `use-the-http-client`, `stream-http-content`, `handle-forms-and-multipart`, `http-limits-timeouts-and-tls`, explanation `http-model`. Carried findings: (1) `problem.lua:71` maps transport errors to a fixed 500 detail (`problem_test.lua`); (2) `Semaphore(max_handshakes)`, `tls.accept` in the forked connection, handshake byte budget (`server_tls_test.lua`); (3) numeric `host`, default `127.0.0.1` (OQ-69, production checklist); (4) exactly one `Host` (`server_test.lua`, `server_lifecycle_test.lua`); (5) `parser:close()`, read size equal to the parser buffer. Gap: `Request.content` not narrowed (P1). |
| `router` | `packages/router/src`; unit and property tests; `benchmarks/match.lua`; README alpha; how-to `route-requests`. Percent-decoding per segment and dot segments: `path.lua`, `path_test.lua`. |
| `schema` | `packages/schema/src`; 29 unit test files including the official JSON Schema test suite; `benchmarks/validate.lua`; README alpha (unimplemented `refine`, `generate`, `---@meta` marked planned); how-to `validate-with-schemas`, explanation `schemas-and-contracts`; review fixes in [schema-review-package.md](schema-review-package.md). Gaps P2 and P3 (fixed). |
| `container` | `packages/container/src`; unit and property tests, boot cycle detection; README alpha; specification `container.md`; how-to `use-the-container`. No micro-benchmark (P6). |
| `config` | `packages/config/src`; unit tests and `integration/files_test.lua`; README alpha; specification `configuration.md` (logging, error, request and server keys, `limits.max_depth`); how-to `configure-an-application`. |
| `kernel` | `packages/kernel/src` (17 modules); 12 unit and 4 integration test files (shutdown, workers, supervisor, rolling reload); README alpha. First step: `http/serve_request.lua` (OQ-78), `on_response`, no JSON fallback, `log.default()` used by `http`. Points (a) `json.set_max_depth` applied by the application; (b), (d) `kernel/logging.lua`; (c) `wrap_secret`; (e), (f) `results.lua`, `hecate.respond`; (g) `request.lua` `ContentError`; (h) `errors.expose_details`; (i) `problem.define`, problem classes in `responses`; (j) controller `routes` field; (k) route module options; (l) `requests.inputs`; (m) `Supervisor:reload`, `sighup`; (n) fixed signal set, second signal forces the stop, `server.grace_timeout`. Gaps P1 to P3; no how-to yet (P7). |
| `examples/hello` | `main.lua`, `src/hello/init.lua` through the meta-module; `hello_test.lua` (422 with `source`, 201, 404, drain during shutdown) and `workers_test.lua` (two workers, `round_robin`); run by the three `ci` jobs when `kernel` is affected. |
| Benchmarks `plaintext`, `kernel-json` | `benchmarks/scenarios/`, `benchmarks/lib/http_load.lua`; every carried finding judged in [phase-2-benchmarks.md](phase-2-benchmarks.md). |
| `reactor` `offload` | `reactor/offload.lua`, `OffloadError`; `offload_test.lua`, `offload_exit_test.lua`; "Offload" in `concurrency.md`; how-to `offload-cpu-bound-work`; benchmark `reactor/offload`; example `hecate.reactor.offload`. |
| `reactor` multi-process primitives | `spawn`, `ipc.lua`, TCP `reuseport` with `supports_reuseport`; integration tests `ipc`, `process`, `reuseport`; spike OQ-8; how-to `run-processes-and-pass-connections`; example `hecate.reactor.spawn`. |
| Spike OQ-11 | `docs/spikes/OQ-11-doc-tooling.md`, samples, ADR 0012 (Accepted). |
| How-to "Before going to production" | `website/en/how-to/before-going-to-production.md`; gaps found by the safe content audit (S1, S2, S7). |
| Example rules | `tools/lib/examples.lua` (`check-examples`), `tools/harness/examples.lua` used by the ten `examples_test.lua`; rules in `documentation.md` and `website/CLAUDE.md`. |
| Generated reference | `reference_site.lua` `DEFAULT_PACKAGES` covers every Phase 2 package; `website.yml` fails when one is missing. `automation.md` gave the old set (C13). |

`grep -niE "todo|fixme|xxx|not implemented|stub|placeholder"` over the sources of `http`, `router`, `schema`,
`container`, `config`, `kernel`, `hecate` and `reactor` finds no marker: only the `mkdtemp` template `.hs-XXXXXX`,
the reason phrase "Not Implemented" and the glossary definition of a future ("placeholder for the value").

## 2. It works

Every command below ran from this checkout, with `eval "$(luarocks path)"` (the cloud image installs `luv` under
`/opt/lua-5.5`, found only this way).

| Command | Result |
|---|---|
| `check-adr-index`, `check-annotations`, `check-boundaries`, `check-changelog --base origin/main`, `check-docs-examples`, `check-examples`, `check-glossary`, `check-licenses`, `check-links`, `check-lua-constructs`, `check-package-structure`, `check-rockspecs`, `check-versions`, `lint`, `format-check` | ok |
| `gen-catalogue --check`, `gen-llms-txt --check`, `gen-dependency-graph --check` | ok after regeneration in this branch (finding G1) |
| `build-native json`, `build-native doc`, `build-native http`, `build-native net` | ok |
| `setup-luals`, then `typecheck` | ok, zero diagnostics |
| `test` (the 30 packages; 192 test files) | ok, about 60 s |
| `test tools` | ok |
| `test examples/hello` (in process, and two workers with `round_robin`, including a request in flight during the graceful shutdown) | ok |
| `check-examples` and the shared runner `tools/harness/examples.lua` (the two example rules) | ok: every example of `packages/*/examples/`, `examples/` and the website passes both rules |
| `bench plaintext --rounds=1 --duration=3 --warmup=1` | ok: 1000 requests/s offered and served, 0 errors, 0 bad responses, p50 1.19 ms, p99 5.9 ms |
| `bench kernel-json --rounds=1 --duration=3 --warmup=1` | ok: 1000 requests/s, 0 errors, 0 bad responses, p50 1.15 ms, p99 5.5 ms |
| `leaks` (`reactor`, `net`) | ok |
| CI of `main` eb9d9b7 | `ci` green on `ubuntu-latest`, `macos-latest` and `windows-latest` (run 43399777184); `docs`, `website` and `benchmarks` green |

**Exit criteria of the phase.** `examples/hello` runs on the three platforms with N workers (its tests run in the
`Test` step of the three `ci` jobs whenever the kernel is affected, and ran green at eb9d9b7); invalid input yields
RFC 9457 problem details (`422` with `source`, tested by `examples/hello/tests`); the graceful shutdown drains
requests in flight (tested with two workers).

## 3. Coherence

Details in [phase-2-coherence-findings.md](phase-2-coherence-findings.md): 32 findings (C1 to C32), each with its
disposition there. The code agrees with what the specifications say about it (defaults of `http`, `router`, `config`,
`kernel` and the supervisor, the violation codes of `schema`); the findings are project-level status lines still
describing the end of Phase 1, specifications saying "not yet implemented" for what the `kernel` item delivered, and
four points that need the owner (C10, C11, C25, C32, section 5).

## 4. Safe content (OQ-111)

No secret, credential or refused input value reaches a client while `errors.expose_details` is false, and free text
reaches the logs only where OQ-111 (3) allows it. The canary test
`packages/kernel/tests/integration/safe_content_canary_test.lua` (10 tests, `CANARY-7f3a9c`) puts a canary through a
secret configuration value, invalid configuration values, log fields (redacted names and a free-text field), an
action error (message, context, cause), an unencodable problem extension, refused inputs (422, 400, undeclared query
parameter, header, cookie), `expose_details = true`, and a real socket (control character in a header, query,
`Authorization`, `Cookie`); it searches every log record and rendered line (memory, JSON lines and console sinks) and
every response.

| Package | What was checked | Result |
|---|---|---|
| `kernel` | `problems.lua` (`detail`, `title`, 422 `errors`, 500 `debug`, guard logs), `input.lua` refusals, `results.lua` (406, response validation), `logging.lua`, `application.lua`, `supervisor.lua`, `listening.lua` logs, declaration errors | Safe; the `traceback` log field and the `debug` member include the cause chain (S1, S2) |
| `http` | `problem.lua`, `server.lua` and `server_connection.lua` logs, `ParseError`, `fields`, `form`, `multipart`, `cookie`, `media_type`, `content`, `request` errors, `on_response`, `on_error` | Safe; `on_response` gets the target with its query (documented); `on_error` gets the raw error (S7) |
| `router` | `router.lua`, `template.lua` errors | Developer input only |
| `schema` | violation messages; `Schema:check`, `stop_representation`; the pattern warning | Values never quoted; the message of `check` and `represent` names the pointer of the first violation, which can hold a user-supplied key (S3) |
| `container` | `container.lua` errors | Service keys and counts only |
| `config` | `load.lua` violations, `report`, `evaluate`, secret files; `secret.lua` | Secrets replaced or redacted; a runtime error raised by a configuration file is quoted (operator code, boot only) |
| `hecate` | `src/hecate/init.lua` | Re-exports only |
| `reactor` | `offload.lua`, `internal/transfer.lua`, `process.lua`, `ipc.lua` | Key paths and types, never values |

The production checklist covers every Phase 2 configuration key with the default of `config/declaration.lua`; what
it lacked is S1, S2 and S7.

## 5. Open questions

The questions labelled `due:phase-2` were due by the end of this phase, and the gate added three (OQ-120 to OQ-122).
None blocks a Phase 2 deliverable; each is put to the owner in one `needs-decision` issue. The relay decides none of
them. A recommendation of "relabel `due:phase-3`" means the question is a real Phase 3 prerequisite, not a Phase 2
gap.

| Question | Context | Recommendation |
|---|---|---|
| OQ-46, rockspecs ship nothing (`modules = {}`) | `luarocks make` installs no source; `check-rockspecs` does not notice. | (b): leave it to the Phase 3 release item, which extends `check-rockspecs`; relabel `due:phase-3`. |
| OQ-13, standalone CLI executable (research) | Blocks the Phase 3 `cli` v1 item. | A spike at the start of Phase 3, before `cli` v1; relabel `due:phase-3`. |
| OQ-17, split tool for the mirrors (research) | Blocks the Phase 3 mirrors item. | A spike before that item (determinism, speed); relabel `due:phase-3`. |
| OQ-38, theme of `hecate doc build` for user projects | Needed before `hecate doc build` (Phase 3 `doc`). | A site configuration `logo` plus a CSS custom-properties override file now, template overrides later; the hecate marks are never recoloured. |
| OQ-64, `source_revision` stamps of the French pages | Nothing reads them until `check-translations` (Phase 3). | Leave them; `check-translations` decides from content. State the rule in `website/CLAUDE.md`. |
| OQ-69, `host` of `Server` and the first defaults | Owner answer recorded (numeric `host`, `localhost` later); the per-address handshake cap is now a recorded known limitation (P4). | Confirm the recorded defaults and close; `host = "localhost"` and the per-address cap become later items. |
| OQ-73, cryptographically secure random primitive | `multipart` falls back on `math.random` on Windows. | `reactor.random(n)` over luv `random`, before `0.1.0` (Phase 3), used by `multipart`. |
| OQ-75, naming and API review of `http` (one break before 0.1) | Implemented as listed. | Confirm as implemented, before the Phase 3 API freeze. |
| OQ-77, a state error class | Wrong-state use is an `ArgumentError` today. | `core.StateError`, before `0.1.0`; relabel `due:phase-3`. |
| OQ-82, review notes of `http` | Several points; `Request.content` narrowed by this gate (P1); the split of `server.lua` and `client.lua` done by the kernel item. | Close the points the gate and the kernel delivered; carry the rest (one class for content timeouts, the client-side 413) to the Phase 3 API freeze. |
| OQ-120, what free text the logs may carry (new, S1, S3, C25) | Causes in the `traceback` field and `debug.message`; JSON Pointer in `schema` messages, which deviates from OQ-117 (4). | (1) keep the causes, documented (done); (2) no pointer in any message, confirming the deviation. |
| OQ-121, planned Phase 2 work with no roadmap item (new, C10, C11) | Eleven outline pages and three generators marked P2. | Re-mark them P3 and name them in the Phase 3 `doc`, `cli` and website items. |
| OQ-122, default number of workers of `hecate serve` (new, C32) | ADR 0023 says the cores; `server.workers` defaults to 1. | The flag falls back on `server.workers`; the generated production configuration sets the cores. |

OQ-24 had an owner decision (2026-10-27) and is recorded as resolved; its issue is closed.

## 6. Findings and disposition

| Id | Finding | Disposition |
|---|---|---|
| G1 | `packages/README.md` and `llms.txt` were stale (the `container`, `kernel` and `hecate` statuses, the `reactor` summary) and CI never ran `gen-catalogue --check`, `gen-llms-txt --check` or `gen-dependency-graph --check`. | Fixed: regenerated, and the three checks added to the `docs-checks` job and to the static checks of `ci.yml`. |
| G2 | The README status of `kernel` was still `in progress` although its item is ticked; `http`, `router`, `schema`, `container` and `config` gave `implemented`, which is not a status of `packages/README.md` (`specified`, `planned`, `in progress`, `alpha`, `stable`); `hecate` said `implemented` although the standard edition is a Phase 3 item. | Fixed: `alpha` for the six Phase 2 packages (as the Phase 1 packages after their gate), `in progress` for `hecate`. |
| G3 | `bench <scenario> --runs=N` (the option `bench --list` advertises) fails with `unknown argument '--runs=1'`, printed twice, without naming `--rounds`, the option of the scenarios. | Fixed, test first: the task refuses `--runs` for a scenario and names `--rounds=N` (`benchmark_scenario_test.lua`). |
| G4 | Roadmap triage item (`examples/hello` review, dx-reviewer): without the native module of `http`, `Application:serve` failed with `attempt to call a nil value (field 'Server')`. | Fixed, test first: `ModuleError` `http_unavailable` naming `lua tools/run.lua build-native http` (`application_test.lua`, `test_serve_without_the_native_module_of_http_names_the_build_command`). |
| P1 | Completeness: `Request.content` was not narrowed (`http/request.lua:20`, `:30` still `string\|table\|function`), against the kernel item and OQ-76 (b). | To fix in this pull request. |
| P2 | Completeness: `schema` did not fall back on `log.default()` without a `logger` (owner decision OQ-86 (1)); a test locked the deviation in. | Fixed, test first (`pattern_test.lua`), README and specification updated. |
| P3 | Completeness: `json_equal` copied `json.DEFAULT_MAX_DEPTH` at load, so a lowered `limits.max_depth` did not reach it (kernel item point (a)). | Fixed, test first (`equal_depth_test.lua`). |
| P4 | Completeness: the per-address cap on TLS handshakes recommended by OQ-69 was neither built nor carried by a roadmap item. | To defer: recorded in OQ-69 as a known limitation. |
| P5 | Completeness: `automation.md` gave the old `gen-reference` default set. | Same as C13. |
| P6 | Completeness: the container scope opened per request has no micro-benchmark. | To defer to roadmap "Continuous". |
| P7 | Completeness: no how-to for building an application with the kernel; `kernel` and `hecate` have no `examples/`. | To defer to the Phase 3 website item (named there). |
| P8 | Completeness: `schema-review-package.md` still marks s5 and s6 open although both are documented. | To fix in this pull request. |
| S1 | Safe content: the `traceback` log field of an unhandled action error starts with `tostring(err)`, which includes the message of every cause (`problems.lua:191`); the checklist says "its message and the traceback". | Documentation to fix in this pull request; dropping the causes from the field is a code choice for the owner (section 5). The canary test asserts the current behaviour, marked `AUDIT FINDING`. |
| S2 | Safe content: with `expose_details = true`, `debug.message` includes the cause chain (`problems.lua:147`). | Documentation to fix in this pull request. |
| S3 | Safe content: `Schema:check` and `represent` errors name the JSON Pointer of the first violation, which can hold a user-supplied key, while `results.lua` keeps the pointer out on purpose. | To defer: open question for `schema` (section 5). |
| S7 | Safe content: the checklist omits that input refusals are not logged, that path parameters can carry personal data, that `logging.async` drops records past 1024 silently, that the `file` sink uses the umask and has no rotation, and that `server.on_error` receives the raw error. | To fix in this pull request. |
| G5 | `coverage`: `reactor` at 89.8 %, under its 90 % threshold, here and in the nightly of eb9d9b7 (run 43403344037, job `coverage` failed): the body of `offload` that runs on a pool thread (52 lines) is never seen by the line hook. | Fixed, test first: `coverage` leaves out a `-- coverage: off` / `-- coverage: on` region (`coverage_test.lua`), used only around that body; `reactor` 90.8 %. |
