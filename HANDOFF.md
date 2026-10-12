# Handoff

- roadmap_item: CI: GitHub Actions matrix {ubuntu, macos, windows} × Lua 5.5, C toolchains, sanitizers on Linux.
- status: waiting-owner
- lock_until: 2026-10-12T13:11:48Z
- last_update: 2026-10-12T12:25:11Z

## Done

- LuaLS 3.19.1 pinned in ci.yml; typecheck task accepts "no problems found".
- Interim `.github/workflows/ci.yml` (3-OS matrix, cached bootstrap, existing tasks).

## Next steps

1. DONE: CI green on 3 platforms with LuaLS typecheck (head 859c93f).
2. Format: OQ-3 resolved (no repository formatter), so `format-check` is not added to CI.
3. C toolchain and Linux sanitizer jobs once packages have csrc/ (Phase 1); then tick the item.

## Decisions taken

- Interim job runs all packages; `affected`/`matrix` tasks come later.

## Doubts and questions for the owner

- None. LuaLS download works once the repo is reachable via add_repo (read).

## Commands to re-run

```sh
lua tools/run.lua test
```
