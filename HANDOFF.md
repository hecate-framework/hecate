# Handoff

- roadmap_item: CI: GitHub Actions matrix {ubuntu, macos, windows} × Lua 5.5, C toolchains, sanitizers on Linux.
- status: in-progress
- lock_until: 2026-10-12T13:11:48Z
- last_update: 2026-10-12T11:41:48Z

## Done

- Interim `.github/workflows/ci.yml` (3-OS matrix, cached bootstrap, existing tasks).

## Next steps

1. Windows run 1 failed: luarocks not on PATH (fixed with pwsh PATH + LUAROCKS_CONFIG); watch run 2 and macOS/Ubuntu results.
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
