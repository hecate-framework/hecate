# Handoff

- roadmap_item: CI: GitHub Actions matrix {ubuntu, macos, windows} × Lua 5.5, C toolchains, sanitizers on Linux.
- status: in-progress
- lock_until: 2026-10-12T13:11:48Z
- last_update: 2026-10-12T12:15:36Z

## Done

- Interim `.github/workflows/ci.yml` (3-OS matrix, cached bootstrap, existing tasks).

## Next steps

1. Add a `typecheck` step to ci.yml: install a pinned LuaLS release (version + SHA-256 per
   platform in a tools/bootstrap script, like Lua/LuaRocks). BLOCKED: github.com release
   download returned 403 from the cloud proxy, so the checksum cannot be computed here.
2. Format: OQ-3 resolved (no repository formatter), so `format-check` is not added to CI.
3. C toolchain and Linux sanitizer jobs once packages have csrc/ (Phase 1); then tick the item.

## Decisions taken

- Interim job runs all packages; `affected`/`matrix` tasks come later.

## Doubts and questions for the owner

- Need network allowlist access to github.com/LuaLS/lua-language-server releases (and its
  objects.githubusercontent.com download host) to pin LuaLS in the bootstrap.

## Commands to re-run

```sh
lua tools/run.lua test
```
