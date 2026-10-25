<!-- Relay handoff note. Lives only on relay branches; deleted before review. -->
# Handoff

- roadmap_item: Workflows `native.yml`, `security.yml`, `nightly.yml`; tasks `sanitize`, `fuzz`, `leaks`, `coverage`, `bench`, `check-licenses`.
- status: in-progress
- lock_until: 2026-10-25T15:50:39Z
- last_update: 2026-10-25T14:20:39Z

## Done

- Claimed the item (no open relay pull request had work left: #29 and #31 wait on the owner).
- Step 1 done: `bench` task already exists; missing tasks are `sanitize`, `fuzz`, `leaks`, `coverage`, `check-licenses` (spec: automation.md lines 46-60, 97-108). Existing workflows: ci, claude, docs, labels, pr-hygiene, security, website.

- Step 2 done: `sanitize` task (tools/lib/sanitize.lua, tests, HECATE_SANITIZE in build-native), verified locally on json. #29 merged; #31 waits on the owner.

- Step 3 done: `check-licenses` task (tools/lib/licenses.lua, tests).

- Step 4 done: `fuzz` task (tools/lib/fuzz.lua, tests) wrapping the cargo-fuzz targets of net; json C libFuzzer target still to write.

- Step 5 done: `leaks` task (tools/lib/leaks.lua, harness `on_finish` hook, `HECATE_TEST_LEAKS` in run_file.lua, tests). Verified with luv installed (`luarocks --tree .hecate/rocks install luv 1.53.0-0`): it found a handle leaked by the net tcp test spy helper (fixed); `leaks`, reactor and net tests pass.

- Merged origin/main (conflicts in CHANGELOG.md and automation.md resolved).

- Resumed after lock expiry; merged origin/main. Step 6 done: `coverage` task (tools/lib/coverage.lua, harness hook `HECATE_TEST_COVERAGE`, tests; core measures 93.2 %). Executable lines are approximated from source text.

- Step 7 done: `native.yml` and `nightly.yml` written (YAML parses; not yet run on GitHub). No artefact upload: the `upload-artifact` hash was not taken from the repo.

- CI fixes after the first run of native.yml (all green on 82030c5): sanitizer builds trap on UB (`-fsanitize-undefined-trap-on-error`, Clang's ASan runtime has no UBSan handlers), JSON corpus fetched, fuzz binaries link the toolchain Lua (`LUA_LIB`, packages/net/native/fuzz/build.rs), `fuzz --list` status line filtered.
- Step 8 done: `security.yml` gains codeql (c-cpp, build-mode none), dependency-review (PRs) and scorecard (push/schedule); pins taken from `git ls-remote` of the upstream tags; LCOV and fuzz artefact uploads restored in nightly.yml (upload-artifact v7.0.1).

## Next steps

1. Watch CI of security.yml's new jobs (CodeQL/Scorecard need code scanning enabled in Settings > Code security; if they fail for that reason, tell the owner).
2. json libFuzzer C target: not part of this PR unless the owner wants it; propose a separate roadmap item.
3. Then: delete HANDOFF.md, tick the roadmap item, mark ready for review, ask for the owner's review.

## Doubts and questions for the owner

- Is code scanning enabled for the repository? CodeQL and Scorecard upload SARIF.

## Commands to re-run

```sh
lua tools/run.lua --list
```
