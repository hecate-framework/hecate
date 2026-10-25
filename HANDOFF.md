<!-- Relay handoff note. Lives only on relay branches; deleted before review. -->
# Handoff

- roadmap_item: Workflows `native.yml`, `security.yml`, `nightly.yml`; tasks `sanitize`, `fuzz`, `leaks`, `coverage`, `bench`, `check-licenses`.
- status: in-progress
- lock_until: 2026-10-25T15:18:33Z
- last_update: 2026-10-25T13:48:33Z

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

## Next steps

1. Watch CI of the new workflows (native.yml runs on this PR because it touches its own file); fix failures.
2. Complete `security.yml` (CodeQL for C, dependency review, Scorecard) with pinned action hashes verified from the actions' repositories.
3. json libFuzzer C target (optional follow-up; may become its own roadmap item).
4. Then: delete HANDOFF.md, tick the roadmap item, mark ready for review.

## Decisions taken (and where they are recorded)

## Doubts and questions for the owner

## Commands to re-run

```sh
lua tools/run.lua --list
```
