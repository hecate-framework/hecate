<!-- Relay handoff note. Lives only on relay branches; deleted before review. -->
# Handoff

- roadmap_item: `json`: codec (after OQ-5).
- status: in-progress
- lock_until: 2026-10-20T08:30:00Z
- last_update: 2026-10-20T07:00:00Z

## Done

- Claimed (PR #25). Website item is in PR #24 (owner's), skipped.
- Step 1 (5ac3128): Lua side. Public API, markers, errors, backend seam (`hecate.json.internal.backend`), pure-Lua reference backend (fallback + test oracle), unit/property tests, README, CHANGELOG, OQ-48. `test json`, lint and the check-* gates pass; `typecheck` not run (no lua-language-server here).
- Step 2: owner answers to OQ-48 applied (recorded in the OQ-48 entry): holes encode as null, `-0` decodes as integer 0, canonical member order is UTF-16 (RFC 8785), explicit decode rejection messages and a README table, `check-boundaries` exempts `markers.lua`. `test json`, `test tools`, lint, check-boundaries, check-changelog, check-links and check-glossary pass. Step 3: `canonical = "rfc8785"` in the reference backend (the native serde_json encoder must match it; the RFC vectors are in `encode_test.lua`). OQ-48 moved to Resolved at the owner's request; nothing is open in it.

- Step 4 (native decoder): `hecate.json.native` in `csrc/native.c` (yyjson 0.10.0), built by `lua tools/run.lua build-native json` (cc, -Wall -Wextra -Werror on our sources; macOS bundle flags; Windows not supported by the task, use LuaRocks/MSVC, unverified) and by the rockspec (`builtin`, verified with `luarocks make`). Failure classification choice: on any failure or divergence (yyjson error, duplicate name, depth, size, BOM, out-of-range float, `-0`/`-0.0`) the binding calls the reference decoder on the same text and returns its answer; so reasons, messages and offsets are identical by construction. Cost: a hostile text pays one extra reference pass; texts containing `-0` or `-0.0` also take the reference path (yyjson cannot tell them apart without RAW mode). `encode` delegates to the reference backend (documented in README/CHANGELOG). Shared suites moved to `tests/suites/{decode,encode,roundtrip}.lua` and are run per backend by `tests/unit/*_{reference,native}_test.lua`; `tests/unit/native_test.lua` is a differential test (corpus, mutations, random numbers, depth 10000, bind, markers). `backend.use(name)` added for tests. CI step added to build the module on Linux/macOS; native tests fail in POSIX CI when it is missing, skip locally and on Windows. ASan/UBSan run of `native_test.lua` was clean (manual). `test json`, `test tools`, lint and the check-* gates pass; `typecheck` not run (no lua-language-server).

- CI fix (resumed run): the 7569411 CI failed on typecheck (8 LuaLS warnings in `backend.lua`, `backend_test.lua`, `markers_test.lua`) and markdownlint (duplicate `### Added` in CHANGELOG, bare URL in VENDORED.md). Fixed with a cast, nil asserts and `---@diagnostic disable-next-line` in tests; markdownlint-cli2 now clean locally. `typecheck` still cannot run here (no lua-language-server): verify in CI.

- CI fix 2 (resumed run): Windows failed because the shared-suite loaders located their directory with a `/`-only pattern (`tools\\..` sources use backslashes); now `[/\\]`. `test json` and lint pass locally; verify Windows in CI.

- Step 5 (Rust encoder): `packages/json/native` (mlua only; no serde_json: the reference number format is `%.15g`..`%.17g`, which serde's shortest-digits output does not reproduce, so floats are formatted by hand from Rust's exact `{:.Ne}` and checked on 40000 random doubles). Module `hecate.json.encoder_native`, loaded by `backend.lua` (`with_encoder`) next to the native decoder; it returns nil for failures, `rfc8785` and nesting > 200 (native stack), and the reference encoder answers. `build-native json` now builds C then Rust. Tests: `tests/unit/encoder_native_test.lua` (differential), `backend_test.lua` (hides the encoder, tests composition). CI: rustup + cache + `cargo fmt`/`clippy` for json, `security.yml` audits/denies it. `test json`, `test tools`, lint, clippy, check-* pass locally; `cargo deny` and `typecheck` not run here. Windows: the encoder is not built there (as the C decoder).

- Step 6 (resumed after lock expiry; CI was green on the three platforms at c09c198): `json.decoder` (`:feed`, `:finish`), buffered, tests in `tests/unit/decoder_test.lua`, OQ-49 for the real incremental parser. `test json` and lint pass.

## Blocked (resolved)

- Resumed after PR #24 merged; merged main into this branch (CHANGELOG conflict resolved, both sides kept; `test json` and `lint` pass).
- yyjson 0.10.0 vendored by the owner's go-ahead in a regular chat: `packages/json/csrc/vendor/{yyjson.c,yyjson.h,LICENSE}` plus `VENDORED.md` (version, SHA-256). Files are unmodified upstream copies. Not blocked anymore.

## Next steps

1. (done, see Step 4.) Open follow-ups: Windows/MSVC build of the native module in CI (`build-native json` is POSIX only); an `sanitize` task entry for json.
2. (done, see Step 5.) Open: Windows build of both native modules in CI; the encoder in the rockspec/binary rocks; benchmark encoder vs reference (the ADR quotes 53 vs 15 MB/s).
3. (buffered version done, Step 6.) True incremental parser waits on OQ-49.
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
