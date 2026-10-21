<!-- Relay handoff note. Lives only on relay branches; deleted before review. -->
# Handoff

- roadmap_item: `doc` (minimal) and the reference generator, pulled forward from Phase 3 (ADR 0012, OQ-11)
- status: in-progress            <!-- in-progress | waiting-ci | waiting-owner -->
- lock_until: 2026-10-21T21:09:31Z
- last_update: 2026-10-21T19:39:31Z

## Done

- Step 1 done: `doc` uses `hecate.json`, internal codec and its test removed (tests, lint, boundaries pass).
- Claimed. #25 (`json`) is merged; `doc` already has a first slice (renderer, site model, theme, search, reference generator).

- Step 2 done: `SystemFileSystem` over `reactor.fs` (OQ-33 b); runners and tests run inside `reactor.run`; theme files read with `io`; deps/README/rockspec/CLAUDE.md updated; unit and integration tests, lint, boundaries, rockspecs pass.

- Resumed after CI failure (logs not downloadable: blob host blocked by proxy). Merged main (#26 SHA pins); all local gates and full test pass. Pushed to re-run CI; if still red, diagnose from the Actions UI.

- website `build` job failed on `luv` not found: build.lua now puts `.hecate/rocks` on package.path/cpath (like the test harness).

- CI green on ubuntu and macos (windows pending) after the luv path fixes in build.lua/reference.lua.
- Owner (chat): when shipping `doc`, ship the Rust module as prebuilt binaries (ADR 0021 / OQ-41: one binary rock per platform from release CI, source rock builds with cargo as fallback).

- Owner allowed `cargo generate-lockfile` / `cargo build` in `packages/doc/native`. Step 3 done: crate `hecate-doc-native` (mlua, comrak 0.52, syntect 5, two-face 0.4; 68 locked packages) with `render` (GFM, alerts, heading ids, outline, links, safe mode) and `highlight` (`hl-` classes). `cargo test --locked`, clippy, fmt pass. Not yet wired into Lua, rockspec, CI, docs.

- Step 4 done: native `render` returns outline, sections, title, links; callout titles, code toolbar, raw HTML as text, link rewriting. `hecate.doc.markdown`/`highlight` now wrap the module; in-house renderer, inline renderer and lexers removed; `::: name` containers converted to GFM alerts in `website/` (en and fr, structure only) and fixtures; theme CSS uses `markdown-alert-*` and `hl-*`; `build-native doc` task; CI (build + lint on 3 platforms), website workflow and security workflow (audit, deny) cover the crate; README, CLAUDE.md, CHANGELOG updated. All local gates and tests pass.

## Next steps

1. Watch CI of this push: first run of the doc native build on macOS/Windows and of `cargo deny` on the new crate (licences; fix `deny.toml` only with the owner's approval if a licence is new).
2. OQ-37: run the CommonMark/GFM spec examples through the module (vendor data under CC BY-SA 4.0 or fetch in CI like `fetch-fixtures`).
3. Lua 5.5 syntax (`global`, `---@` annotations): syntect renders `global` as a plain variable (see features.html); licence audit of the two-face syntaxes into THIRD_PARTY_NOTICES.
4. Rockspec and release: binary rock per platform (owner: ship the Rust module as prebuilt binaries), source rock builds with cargo.
5. Cosmetic: code language labels come from syntect names ("Bourne Again Shell (bash)" for `sh`); images lost `loading="lazy"`.
6. Reference pages for `core` and `reactor`; website built by `doc` in CI.

## Decisions taken (and where they are recorded)

## Doubts and questions for the owner

- OQ-55 resolved by the owner (2026-10-21): licences allowed, RUSTSEC-2025-0141 ignored with reason in `deny.toml`; upstream (syntect/two-face) has no committed plan to drop bincode (recorded in the OQ). Applied; CI of `rust dependencies` to confirm.

## Commands to re-run

```sh
export LUA_CPATH="/opt/lua-5.5/lib/lua/5.5/?.so;;"   # luv
lua tools/run.lua test doc
(cd packages/doc/native && cargo test --locked && cargo clippy --locked --all-targets && cargo fmt --check)
```
