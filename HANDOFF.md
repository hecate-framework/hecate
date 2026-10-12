# Handoff

- roadmap_item: CI: GitHub Actions matrix {ubuntu, macos, windows} × Lua 5.5, C toolchains, sanitizers on Linux.
- status: in-progress
- lock_until: 2026-10-12T13:10:25Z
- last_update: 2026-10-12T11:40:25Z

## Done

- Interim `.github/workflows/ci.yml` (3-OS matrix, cached bootstrap, existing tasks).

## Next steps

1. Push, open draft PR (label relay, area:ci), watch CI on 3 platforms; fix failures
   (Windows PATH/shell, bootstrap on macOS, binary location on Windows).
2. Add typecheck (needs LuaLS install) and format-check decision (OQ-3).
3. C toolchain and Linux sanitizer jobs once packages have csrc/ (Phase 1); tick item when exit met.

## Decisions taken

- Interim job runs all packages; `affected`/`matrix` tasks come later.

## Doubts and questions for the owner

## Commands to re-run

```sh
lua tools/run.lua test
```
