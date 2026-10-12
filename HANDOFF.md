<!-- Relay handoff note. Lives only on relay branches; deleted before review. -->
# Handoff

- roadmap_item: `reactor`: reactor over luv, scheduler, futures, `fork`/`join`/`select`, deadlines, scopes and cancellation, channels, semaphores, mutexes, monitors, timers, thread-pool offloading, signals
- status: in-progress
- lock_until: 2026-10-12T23:11:51Z
- last_update: 2026-10-12T21:41:51Z

## Done

- Claimed the item (previous item `core` merged in #17).
- Step 1: `Reactor` (real clock over luv + virtual clock), `Future`, `Scope`, `Instant`, `fork`, `join`, `select`, `sleep`, `scope`, `deadline`, cooperative level-triggered cancellation running `<close>` handlers, deadlock detection, non-yieldable detection. `NonYieldableContextError` added to `hecate.core`. `tools/tasks/test.lua` now puts all package `src` dirs on the path. Tests in `packages/reactor/tests/unit`.
- Step 2: fixed the 21 LuaLS diagnostics (variadic return annotations `fun(...): ...`, `Context` fields, targeted suppressions only in tests passing invalid values). CI now installs luv into `.hecate/rocks` (cached); `tools/harness/run_file.lua` adds `.hecate/rocks` and `spikes/rocks` to package.path/cpath. LuaLS 3.19.1 installed locally in `spikes/luals`.

## Next steps

1. Step 2: `Channel` (capacity 0 rendezvous, usable in `select`), `Semaphore`, `Mutex` (`<close>`-able permits), `Monitor`, `Condition`.
2. Step 3: `detach`, timers/handles API, signals, processes, file-system operations as suspending calls; leak-detection of libuv handles for these.
3. Step 4: `offload` design (spec before implementation), worker primitives (OQ-8), benchmarks, website reference, tick roadmap item, delete this file.
4. Confirm CI is green on the three platforms (luv install step and LuaLS were verified only on Linux).

## Decisions taken (and where they are recorded)

- Absolute instants for `deadline`: `reactor.at(seconds)`; OQ-22.
- Level-triggered cancellation, no shielding yet: OQ-23.
- Strict failure propagation (a failed child always fails its scope): OQ-24.

## Doubts and questions for the owner

- Installed luv is 1.52.1-0 (HANDOFF originally said >= 1.53.0-0); it works with Lua 5.5.1 for the current code.
- `core` was touched (NonYieldableContextError) as the task asked; `tools/tasks/test.lua` was touched to wire dependencies.

## Commands to re-run

```sh
eval "$(luarocks --tree spikes/rocks path | grep -E '^export LUA_(PATH|CPATH)')"
lua tools/run.lua test reactor core
lua tools/run.lua lint
lua tools/run.lua check-boundaries
lua tools/run.lua check-glossary
```
