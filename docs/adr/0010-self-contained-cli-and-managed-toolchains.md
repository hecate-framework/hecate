# 0010 — Self-contained CLI executable managing Lua toolchains

- **Status:** Accepted
- **Date:** 2026-10-11
- **Deciders:** project owner
- **Packages:** cli
- **Related:** [cli-and-packaging.md](../architecture/cli-and-packaging.md), OQ-13

## Context

Lua 5.5 is not yet packaged everywhere. Adoption depends on a single, simple
installation on Linux, macOS and Windows, comparable to `rustup` or `uv`.

## Decision

- `hecate` is distributed as one executable per platform embedding Lua 5.5, the CLI
  modules and the native modules it needs.
- It installs and manages toolchains (Lua + LuaRocks + headers) per version under a
  user directory and pins them per project (`lua = "5.5"` in the manifest).
- Installation channels: shell installer, Homebrew, winget, Scoop, Docker images,
  GitHub release archives; `luarocks install hecate-cli` remains available.
- `hecate version` and `hecate doctor` print the Hecate version, Lua version, LuaRocks
  version, libuv version and platform.

## Consequences

- Release pipeline builds and signs binaries for six targets
  (linux/macos/windows × x86_64/arm64).
- The CLI never relies on a system Lua.

## Verification

Release smoke test on clean runners: install → `hecate new` → `hecate test` → `hecate serve`.
