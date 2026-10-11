# 0009 — Lua project manifest and lockfile on top of LuaRocks

- **Status:** Accepted
- **Date:** 2026-10-11
- **Deciders:** project owner
- **Packages:** cli
- **Related:** [cli-and-packaging.md](../architecture/cli-and-packaging.md), OQ-2

## Context

The owner wants a composer/npm-like experience: a project file listing dependencies and
one command to install everything, using LuaRocks extensively.

## Options considered

1. **TOML/JSON manifest.** Data-only, familiar; needs a parser bundled in the CLI;
   alien to the Lua ecosystem (rockspecs are Lua).
2. **Lua manifest `hecate.project.lua`** evaluated in an empty sandbox (no globals, no
   `require`, instruction-count limit): idiomatic, comments allowed, trivially parsed by
   the CLI.
3. **A rockspec as manifest.** Designed for publishing libraries, not for applications
   (no dev dependencies grouping, no scripts, no toolchain pin).

## Decision

Option 2.

- `hecate.project.lua` declares name, version, `lua` line, dependencies, development
  dependencies, scripts, contract metadata and toolchain settings.
- `hecate.lock` records exact versions, sources and checksums for every rock, including
  transitive ones, plus the Lua and LuaRocks versions used.
- Installation delegates to LuaRocks with a project-local tree (`lua_modules/`) and an
  isolated configuration; constraints use LuaRocks syntax unchanged.
- Libraries published by users still need a rockspec; `hecate package` generates it
  from the manifest.

## Verification

CLI integration tests: `install` from a lockfile is reproducible bit-for-bit on the
three platforms.
