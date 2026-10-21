<!-- Relay handoff note. Lives only on relay branches; deleted before review. -->
# Handoff

- roadmap_item: `doc` (minimal) and the reference generator, pulled forward from Phase 3 (ADR 0012, OQ-11)
- status: waiting-owner            <!-- in-progress | waiting-ci | waiting-owner -->
- lock_until: 2026-10-21T18:56:16Z
- last_update: 2026-10-21T18:56:16Z

## Done

- Step 1 done: `doc` uses `hecate.json`, internal codec and its test removed (tests, lint, boundaries pass).
- Claimed. #25 (`json`) is merged; `doc` already has a first slice (renderer, site model, theme, search, reference generator).

- Step 2 done: `SystemFileSystem` over `reactor.fs` (OQ-33 b); runners and tests run inside `reactor.run`; theme files read with `io`; deps/README/rockspec/CLAUDE.md updated; unit and integration tests, lint, boundaries, rockspecs pass.

- Resumed after CI failure (logs not downloadable: blob host blocked by proxy). Merged main (#26 SHA pins); all local gates and full test pass. Pushed to re-run CI; if still red, diagnose from the Actions UI.

- website `build` job failed on `luv` not found: build.lua now puts `.hecate/rocks` on package.path/cpath (like the test harness).

- CI green on ubuntu and macos (windows pending) after the luv path fixes in build.lua/reference.lua.
- Owner (chat): when shipping `doc`, ship the Rust module as prebuilt binaries (ADR 0021 / OQ-41: one binary rock per platform from release CI, source rock builds with cargo as fallback).

## Blocked

Step "native module" (ADR 0022). `cargo` 1.97.0 is installed. Denied by the auto-mode classifier
(reason "Untrusted Code Integration"): creating `packages/doc/native/{Cargo.toml,rust-toolchain.toml,src/lib.rs}`
(mlua 0.12 lua55+module, comrak 0.52, syntect 5 regex-fancy, two-face 0.4, layout copied from `packages/net/native`)
chained with `cd packages/doc/native && cargo generate-lockfile` (downloads crates). Nothing was created. Not retried.
Needs the owner to allow `cargo generate-lockfile` / `cargo build` in `packages/doc/native` (crates.io), or to run it.

## Next steps

1. Integrate the ADR 0022 native module (comrak, syntect) in steps (needs the Rust toolchain; check `cargo` is available).
2. Reference pages for `core` and `reactor`; website built by `doc` in CI.

## Decisions taken (and where they are recorded)

## Doubts and questions for the owner

## Commands to re-run

```sh
export LUA_CPATH="/opt/lua-5.5/lib/lua/5.5/?.so;;"   # luv
lua tools/run.lua test doc
```
