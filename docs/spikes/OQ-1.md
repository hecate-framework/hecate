# Spike OQ-1: luv on Lua 5.5

Status: **complete**. Recommendation submitted to the owner.

## Method

luv 1.53.0-0 (with bundled libuv) built as a Lua module with CMake against a system
Lua 5.5.1 (`LUA_BUILD_TYPE=System`, `WITH_LUA_ENGINE=Lua`), then `tests/run.lua`.
CI job: `.github/workflows/spike-oq1.yml` (ubuntu, macos, windows).

## Results

| Platform | Build | Tests |
|---|---|---|
| Linux x86_64 (GCC) | OK, no errors | 167/167 passed ("All tests passed") |
| macOS (CI, `macos-latest`) | OK | all tests passed |
| Windows (CI, `windows-latest`, MSVC) | OK | all tests passed |

No patch to luv was needed on any platform. CI run: PR #4, workflow `spike-oq1`
(removed with the spike; it is in the PR history). Lua 5.5.1 was built from the
official tarball with a minimal CMake wrapper.

## Recommendation

Use luv unmodified (1.53.0-0 or later, system Lua mode). No fork or dedicated binding
is needed. Decision on OQ-1 is the owner's.
