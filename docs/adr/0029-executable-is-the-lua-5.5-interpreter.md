# 0029 — The `hecate` executable embeds Lua and LuaRocks and is the interpreter of Lua 5.5 projects

- **Status:** Proposed
- **Date:** 2026-11-14
- **Deciders:** project owner
- **Packages:** cli
- **Related:** [ADR 0010](0010-self-contained-cli-and-managed-toolchains.md) (amended on one point), [ADR 0028](0028-cli-sha256-rock-behind-a-seam.md), [spike OQ-13](../spikes/OQ-13-standalone-executable.md), OQ-13, OQ-131 (issue [#205](https://github.com/hecate-framework/hecate/issues/205))

## Context

ADR 0010 has the CLI install a toolchain (Lua, LuaRocks and headers) per project under `~/.hecate/toolchains/`,
because LuaRocks cannot fetch its own interpreter. The owner asked what really has to be downloaded, given that rocks
all go through LuaRocks, and decided on 2026-11-14 that the Lua and LuaRocks binaries are included in the executable
too. The spike OQ-13 (seventh round) checked on Linux that a host program embedding Lua 5.5 and linked with the Lua
API exported loads a separately built native rock, and runs LuaRocks 3.13 itself to install a binary rock into a tree.
Not checked: Windows, where native rocks link against `lua55.dll`; macOS; building a source rock (needs the Lua
headers and a compiler); Lua 5.4.

## Options considered

1. **A toolchain per project, downloaded** (ADR 0010 as written). Consequences: a download and an unpack step on first
   use; prebuilt toolchain archives per platform and architecture to build and publish for every Lua version.
2. **Embed only the CLI's own interpreter and download the toolchain.** Consequences: the same downloads as option 1;
   the embedded interpreter only runs the CLI.
3. **Embed Lua and LuaRocks; the executable is the interpreter of a Lua 5.5 project.** Consequences: nothing to download
   for the default Lua; the executable must export the Lua API to native rocks (on Windows under the name they link
   against); toolchain archives are needed only for other Lua versions.

## Decision

- The executable embeds Lua 5.5 and LuaRocks (pure Lua) and can act as `lua` and `luarocks` for a Lua 5.5 project:
  `hecate install` runs LuaRocks inside it, and the application and tools of the project run on it.
- The framework packages and the native modules remain the project's rocks, installed into the project's tree as
  before; native modules ship as binary rocks (OQ-41).
- A downloaded toolchain is only for a Lua version the executable does not embed (Lua 5.4, once supported); the
  `toolchain` command then installs it as ADR 0010 describes. On that point only, this ADR amends ADR 0010; the rest of
  ADR 0010 stands (one executable per platform, managed toolchains for other versions, `version` and `doctor`).
- The executable's own libraries (for example `digest`, ADR 0028) are not visible to the project: the project's
  `package.path` and `package.cpath` point at its tree, so the CLI's modules and the project's `hecate.*` rocks are not
  mixed (to be enforced by running project code as OQ-132 decides).

## Consequences

- No toolchain archive to publish for Lua 5.5, no first-use download of an interpreter, one file to install and sign.
- Source rocks that compile C need the Lua headers and a compiler; the executable can carry the headers and extract them
  on demand (to verify), and binary rocks avoid the case.
- Binary rocks must be built against the interface the executable exports; a rock built against the official
  `lua55.dll` on Windows would not load unless the executable provides that interface (to verify, see below).
- `docs/architecture/cli-and-packaging.md` (environment layout) is updated with the `cli` v1 item; a note points here.

## Verification

Before this ADR is accepted, a throwaway workflow on Linux, macOS and Windows must show that the executable loads a
native binary rock built by the release CI (on Windows, against the interface the executable exports), runs LuaRocks
and installs a rock, and builds a small source rock with the embedded headers. A failure on one platform reopens
option 1 for that platform.
