<!-- Relay handoff note. Lives only on relay branches; deleted before review. -->
# Handoff

- roadmap_item: `kernel`: application, modules, controllers, route modules, filters, problem details, lifecycle, multi-process workers, graceful shutdown (Phase 2, docs/roadmap.md)
- status: in-progress
- lock_until: 2026-11-09T20:30:00Z
- last_update: 2026-11-09T19:10:00Z

## Done

- Claimed the item (previous relay branch was already merged into main via PR #162/#165); draft PR #166 opened (labels relay, package:kernel, package:http).
- Step 1: split http `server.lua`/`client.lua` into `internal/` modules, no API change (typecheck and `test http` ok; macOS/Windows CI and benchmarks pending).

- CI of PR #166 green on the three platforms at 69069b1.
- Step 2a: `log.default()` / `log.set_default()` (OQ-79), tests in `packages/log/tests/unit/default_logger_test.lua`.
- Step 3 (owner request): split `schema/schema.lua` (2081 to 109 lines) into `internal/` modules, no API change; typecheck, lint and `test schema` ok. `validation.lua` (1164 lines) stays large on purpose: shared upvalue state on the hot path. Benchmark `validate.lua` class-bound `BenchPerson` scenario fails (reported as also failing before the split; not verified by me). `test doc` needs the native module (no Rust here).
- Step 4: `http.dispatch` (OQ-78), writer split into pure `normalise` + write, JSON fallback removed (OQ-76 a), `log.default()` used by the server when no `logger` is given (OQ-79). Tests in `packages/http/tests/unit/dispatch_test.lua` and `server_lifecycle_test.lua`; typecheck, lint, `test http`, `test log` ok. No writer benchmark exists here (only `http/parse`, `http/forms`, `tcp-echo`, `accept-spread`).
- Step 5a: `on_response` hook (OQ-81) in `server_response.lua`, tests in `server_lifecycle_test.lua`; typecheck, lint, `test http` ok (needs `build-native http json`). Website reference page for the option not yet updated.
- CI green at 26e4200. Step 5b: `json.set_max_depth` (OQ-101 a), `schema` reads `json.DEFAULT_MAX_DEPTH`; tests in `packages/json/tests/unit/max_depth_test.lua` and `deep_test.lua`; typecheck, lint, `test json`, `test schema` ok.

## Next steps

1. `Request.content` (OQ-76 b): the server already leaves it nil; the type stays `string|table|function` because the kernel sets the validated content, so nothing to narrow in `http` (decide in the kernel step).
2. OQ-101 items (b) logging keys, (c) `wrap_secret`; (a) kernel must call `json.set_max_depth(limits.max_depth)` at boot.
3. Settle how a route names its response schema (OQ-98 item 7), then the kernel proper.

## Decisions taken (and where they are recorded)

- Worked on the session-designated branch `claude/sweet-feynman-h1j6tu` instead of `claude/relay-kernel` (session instruction).

## Doubts and questions for the owner

- `dispatch` is a provisional name (OQ-78): the glossary has no such term.
- The server logs `tostring(failure)` of an unhandled action error in the field `error`; `ConsoleSink` redacts by field name, not content, so a secret inside an error message would reach the log (the client never sees it). Not yet in `docs/open-questions.md`: decide whether to add an entry.
- `Response(200, { content = table })` is still accepted by the `Response` constructor (only the server and `dispatch` refuse it); the kernel step decides whether to narrow it.

- The run was triggered by a bare "Retry" message with no task text; I assumed the relay routine and started the first unchecked roadmap item.

## Commands to re-run

```sh
eval "$(luarocks path)"        # luv is only found after this (tools/cloud/README.md)
lua tools/run.lua setup-luals   # once per session: pinned LuaLS into spikes/luals
lua tools/run.lua typecheck     # required before every push (CI fails on any warning)
```
