<!-- Relay handoff note. Lives only on relay branches; deleted before review. -->
# Handoff

- roadmap_item: `json`: codec (after OQ-5).
- status: in-progress
- lock_until: 2026-10-19T23:12:45Z
- last_update: 2026-10-19T21:42:45Z

## Done

- Claimed (PR #25). Website item is in PR #24 (owner's), skipped.
- Step 1 (5ac3128): Lua side. Public API, markers, errors, backend seam (`hecate.json.internal.backend`), pure-Lua reference backend (fallback + test oracle), unit/property tests, README, CHANGELOG, OQ-48. `test json`, lint and the check-* gates pass; `typecheck` not run (no lua-language-server here).
- Step 2: owner answers to OQ-48 applied (recorded in the OQ-48 entry): holes encode as null, `-0` decodes as integer 0, canonical member order is UTF-16 (RFC 8785), explicit decode rejection messages and a README table, `check-boundaries` exempts `markers.lua`. `test json`, `test tools`, lint, check-boundaries, check-changelog, check-links and check-glossary pass. Step 3: `canonical = "rfc8785"` in the reference backend (the native serde_json encoder must match it; the RFC vectors are in `encode_test.lua`). OQ-48 moved to Resolved at the owner's request; nothing is open in it.

- Step 4 (native decoder): `hecate.json.native` in `csrc/native.c` (yyjson 0.10.0), built by `lua tools/run.lua build-native json` (cc, -Wall -Wextra -Werror on our sources; macOS bundle flags; Windows not supported by the task, use LuaRocks/MSVC, unverified) and by the rockspec (`builtin`, verified with `luarocks make`). Failure classification choice: on any failure or divergence (yyjson error, duplicate name, depth, size, BOM, out-of-range float, `-0`/`-0.0`) the binding calls the reference decoder on the same text and returns its answer; so reasons, messages and offsets are identical by construction. Cost: a hostile text pays one extra reference pass; texts containing `-0` or `-0.0` also take the reference path (yyjson cannot tell them apart without RAW mode). `encode` delegates to the reference backend (documented in README/CHANGELOG). Shared suites moved to `tests/suites/{decode,encode,roundtrip}.lua` and are run per backend by `tests/unit/*_{reference,native}_test.lua`; `tests/unit/native_test.lua` is a differential test (corpus, mutations, random numbers, depth 10000, bind, markers). `backend.use(name)` added for tests. CI step added to build the module on Linux/macOS; native tests fail in POSIX CI when it is missing, skip locally and on Windows. ASan/UBSan run of `native_test.lua` was clean (manual). `test json`, `test tools`, lint and the check-* gates pass; `typecheck` not run (no lua-language-server).

- CI fix (resumed run): the 7569411 CI failed on typecheck (8 LuaLS warnings in `backend.lua`, `backend_test.lua`, `markers_test.lua`) and markdownlint (duplicate `### Added` in CHANGELOG, bare URL in VENDORED.md). Fixed with a cast, nil asserts and `---@diagnostic disable-next-line` in tests; markdownlint-cli2 now clean locally. `typecheck` still cannot run here (no lua-language-server): verify in CI.

## Blocked (resolved)

- Resumed after PR #24 merged; merged main into this branch (CHANGELOG conflict resolved, both sides kept; `test json` and `lint` pass).
- yyjson 0.10.0 vendored by the owner's go-ahead in a regular chat: `packages/json/csrc/vendor/{yyjson.c,yyjson.h,LICENSE}` plus `VENDORED.md` (version, SHA-256). Files are unmodified upstream copies. Not blocked anymore.

## Next steps

1. (done, see Step 4.) Open follow-ups: Windows/MSVC build of the native module in CI (`build-native json` is POSIX only); an `sanitize` task entry for json.
2. serde_json encoder via mlua (ADR 0021) in `packages/json/native`, matching float formatting and markers.
3. Streaming/incremental decoder.
4. JSONTestSuite corpus in tests/fixtures, run on both backends; fuzzing.
5. Benchmarks, website reference page, examples for the doc generator.

## Decisions taken (and where they are recorded)

- Work is on the session branch `claude/sweet-feynman-1zqg2u`, not `claude/relay-json`.
- Defaults (max_depth 1000/ceiling 10000, max_size 16 MiB, canonical = byte order) in OQ-48.

## Doubts and questions for the owner

- OQ-48: empty unmarked table encodes as {}; `markers.lua` aliases setmetatable to get past check-boundaries (owner: allow json in the check, or a core tagging primitive); error root JsonError; is_array/is_object exported.

## Commands to re-run

```sh
lua tools/run.lua test json
lua tools/run.lua lint
lua tools/run.lua check-boundaries
```
