<!-- Relay handoff note. Lives only on relay branches; deleted before review. -->
# Handoff

- roadmap_item: Example: `examples/hello` (JSON API with validation).
- status: in-progress
- lock_until: 2026-11-12T05:25:10Z
- last_update: 2026-11-12T03:55:10Z

Stacked on the `kernel` pull request (#166, branch `claude/sweet-feynman-h1j6tu`), which is ready for review
but not merged: this pull request targets that branch until #166 is merged, then `main`.

## Done

- Found that the `kernel` pull request already delivered most of the example (commits 7378897, c584e7f, 6293e65):
  `examples/hello` (controller and route module, path and content validation, 422 problem details with `source`,
  `201` through `kernel.respond`, `/health`, 404), `tests/hello_test.lua` (in process) and `tests/workers_test.lua`
  (two workers from `main.lua`, `round_robin`), run by CI on three platforms when `kernel` is affected. What is
  left is the gap list below.
- `tools/lib/affected.lua`: a change to an example (not Markdown) now affects `kernel`, so CI runs the example; before,
  a change under `examples/` alone ran no test of it (test first in `tools/tests/affected_test.lua`).

- Exit criterion "graceful shutdown drains in-flight requests": `tests/helpers/wire.lua` and one test in each of
  `hello_test.lua` and `workers_test.lua` (content sent in two parts around `Application:shutdown`; 201 with
  `Connection: close`, new connections refused). Checked that a zero grace fails it; 5 runs of each file green.

- `examples/README.md`: the "complete project, `hecate test`, `hecate contract lint`" rule applies from Phase 3; until
  then `lua main.lua` and the harness. Carried to the Phase 3 `cli` item (turn `hello` into a project) and the Phase 3
  website item (the getting-started tutorial walks through `hello`): no tutorial now, the website has no tutorials
  section and "reproducible verbatim" needs `hecate new`.

- test-engineer review: the drain tests no longer guess timings (`Expect: 100-continue` marks the request in flight;
  idle kept-alive connections, two per worker, close when each server begins its shutdown, as the primary closes its
  listener before it sends `stop`); both workers ready before the requests and both served (supervisor counters);
  the 422 of the workers test checks `application/problem+json`; polling loops bounded. 5 runs of each file green.

- dx-reviewer review: the example uses the meta-module `hecate`; README Run section rewritten and run verbatim from a
  clean environment (two workers, `curl`, SIGTERM, exit 0); 422 wording; `prefix = ""` dropped; asserts commented;
  no "listening" line before the bind (the server logs it); "grace period" instead of "drain" (glossary). The cryptic
  error without the `http` native module is carried to the Phase 2 gate item (kernel/http, not this item).

## Next steps

1. CI green on Linux, macOS and Windows for the latest commit; then delete `HANDOFF.md`, tick the roadmap item, mark
   the pull request ready and ask for the owner's review (stacked on #166).

## Decisions taken (and where they are recorded)

- Stacked on #166: the item depends on `kernel`, ticked there and ready for review but not merged.
- No website tutorial in this item: the getting-started tutorial walks through `hello` in the Phase 3 website item
  (recorded there in `docs/roadmap.md`); turning `hello` into a `hecate.project.lua` project goes to the Phase 3 `cli`
  item (recorded there); `examples/README.md` says what a Phase 2 example is.

## Doubts and questions for the owner

## Commands to re-run

```sh
lua tools/run.lua setup-luals   # once per session: pinned LuaLS into spikes/luals
lua tools/run.lua typecheck     # required before every push (CI fails on any warning)
eval "$(luarocks path)"         # luv is found only this way in the cloud image
lua tools/run.lua build-native json; lua tools/run.lua build-native http; lua tools/run.lua build-native net
export LUA_CPATH="$PWD/.hecate/rocks/lib/lua/5.5/?.so;$LUA_CPATH"
lua tools/run.lua test examples/hello
```
