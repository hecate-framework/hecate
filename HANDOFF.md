<!-- Relay handoff note. Lives only on relay branches; deleted before review. -->
# Handoff

- roadmap_item: `doc` (minimal) and the reference generator, pulled forward from Phase 3 (ADR 0012, OQ-11)
- status: in-progress            <!-- in-progress | waiting-ci | waiting-owner -->
- lock_until: 2026-10-21T20:29:28Z
- last_update: 2026-10-21T18:59:28Z

## Done

- Step 1 done: `doc` uses `hecate.json`, internal codec and its test removed (tests, lint, boundaries pass).
- Claimed. #25 (`json`) is merged; `doc` already has a first slice (renderer, site model, theme, search, reference generator).

- Step 2 done: `SystemFileSystem` over `reactor.fs` (OQ-33 b); runners and tests run inside `reactor.run`; theme files read with `io`; deps/README/rockspec/CLAUDE.md updated; unit and integration tests, lint, boundaries, rockspecs pass.

- Resumed after CI failure (logs not downloadable: blob host blocked by proxy). Merged main (#26 SHA pins); all local gates and full test pass. Pushed to re-run CI; if still red, diagnose from the Actions UI.

- website `build` job failed on `luv` not found: build.lua now puts `.hecate/rocks` on package.path/cpath (like the test harness).

- CI green on ubuntu and macos (windows pending) after the luv path fixes in build.lua/reference.lua.
- Owner (chat): when shipping `doc`, ship the Rust module as prebuilt binaries (ADR 0021 / OQ-41: one binary rock per platform from release CI, source rock builds with cargo as fallback).

- Owner allowed `cargo generate-lockfile` / `cargo build` in `packages/doc/native`. Step 3 done: crate `hecate-doc-native` (mlua, comrak 0.52, syntect 5, two-face 0.4; 68 locked packages) with `render` (GFM, alerts, heading ids, outline, links, safe mode) and `highlight` (`hl-` classes). `cargo test --locked`, clippy, fmt pass. Not yet wired into Lua, rockspec, CI, docs.

## Next steps

1. Load `hecate_doc_native` from Lua (build to `.hecate/rocks/lib/lua/5.5/hecate/doc/`), replace the in-house Markdown renderer and highlighters, migrate `::: note` to GFM alerts, golden tests; CommonMark/GFM spec examples through the module (OQ-37).
2. CI Rust job for `doc/native` on three platforms (copy the `net` job), `cargo-deny`, licence audit of syntaxes into THIRD_PARTY_NOTICES, rockspec (binary rock per platform from release CI, source rock builds with cargo), packages/doc/CLAUDE.md + README + check-boundaries ("Native code: none" changes: owner approved by ADR 0022 E), CHANGELOG.
3. Reference pages for `core` and `reactor`; website built by `doc` in CI.

## Decisions taken (and where they are recorded)

## Doubts and questions for the owner

## Commands to re-run

```sh
export LUA_CPATH="/opt/lua-5.5/lib/lua/5.5/?.so;;"   # luv
lua tools/run.lua test doc
(cd packages/doc/native && cargo test --locked && cargo clippy --locked --all-targets && cargo fmt --check)
```
