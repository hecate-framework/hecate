# 0029 — The `hecate` executable embeds Lua and LuaRocks and is the interpreter of Lua 5.5 projects

- **Status:** Accepted
- **Date:** 2026-11-14
- **Deciders:** project owner (accepted by the project owner on 2026-11-14, on condition that it be verified on all platforms; verified the same day, see Verification)
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

- No toolchain archive to publish for Lua 5.5, no first-use download of an interpreter, one file to install and sign
  on Linux and macOS.
- **Windows: the interpreter is `lua55.dll`, shipped beside `hecate.exe`** (the setup executable installs both).
  Native rocks on Windows link against `lua55.dll`; the executable links to the same DLL, so they share one interpreter.
  A single-file executable with Lua linked statically would not load native rocks built against the official DLL.
- **Windows: the embedded LuaRocks needs LuaFileSystem (`lfs`, MIT)**, embedded in the executable as a native module.
  Without it, LuaRocks lists the files of a rock with the `find` command, which on Windows is the system's text-search
  tool: the list is empty, nothing is deployed, and a rock reports "installed" but cannot be required. The official
  `luarocks.exe` bundles `lfs` for this reason. It is optional on Linux and macOS, where the Unix tools exist.
  `THIRD_PARTY_NOTICES` records it when it is vendored (a new third-party dependency, accepted with this ADR).
- Owner remark of 2026-11-14: with a setup installer on Windows, shipping `lua55.dll` beside `hecate.exe` and embedding `lfs`
  are not a problem; the installer places everything together.
- Source rocks that compile C need the Lua headers and a compiler; the executable can carry the headers and extract them
  on demand (not checked: the verification used the toolchain's headers), and binary rocks avoid the case.
- Binary rocks must be built against the interface the executable exports (on Windows, `lua55.dll`).
- `docs/architecture/cli-and-packaging.md` (environment layout) is updated with the `cli` v1 item; a note points here.

## Verification

Done on 2026-11-14 by a throwaway workflow of pull request #200 (removed after the run; scripts `verify_interpreter.sh`
and `verify_interpreter.ps1` in [`docs/spikes/OQ-13/`](../spikes/OQ-13/), results in the
[spike report](../spikes/OQ-13-standalone-executable.md)). On Linux x86_64 and arm64, macOS arm64 and x86_64, and Windows
(MSVC, x86_64), a host program embedding Lua 5.5 with the Lua API exported (Windows: linked to `lua55.dll`):

1. loaded a native rock built by the standard toolchain;
2. ran the LuaRocks 3.13.0 sources itself and installed a pure-Lua rock;
3. ran LuaRocks to build a source rock with a C module from the Lua headers, and loaded it;
4. ran the contract test of the sha256 seam (ADR 0028) with the `digest` and `plc` backends.

All passed; on Windows only after `lfs` was available to the host (the first runs failed at step 3, as described above).
Not verified: Windows arm64, musl, Lua 5.4, embedding the LuaRocks sources and the headers in the executable.
