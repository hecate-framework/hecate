# Spike OQ-2: LuaRocks on Lua 5.5

Status: **complete**. Verified on Linux, macOS and Windows. Recommendation submitted to
the owner.

## Question

Does LuaRocks 3.x support Lua 5.5 with project-local trees and lockfiles, and can
`hecate.lock` be a superset of `luarocks.lock`? (OQ-2)

## Method

LuaRocks 3.13.0 with Lua 5.5.1 on Linux x86_64 (cloud session, `spikes/OQ-2/`) and on
the three CI platforms (`ubuntu-latest`, `macos-latest`, `windows-latest`; workflow
`spike-oq2.yml`, removed with the spike, see PR #5 history). Lua was built from the
official tarball with a CMake wrapper (as in OQ-1); LuaRocks 3.13.0 from source (Unix)
or the official Windows zip. The cloud network policy blocks GitHub source archives
(`github.com/*/archive/*` and `codeload.github.com` return 403), so rocks hosted on
GitHub (e.g. `inspect`) cannot be installed in cloud sessions. Dependencies were
therefore served from a local `file://` repository built with `luarocks-admin
make_manifest` (two versions of a pure-Lua rock, `dep-a` 1.0 and 1.1).

## Findings

| Capability | Result |
|---|---|
| Lua 5.5 recognised | Yes: `luarocks config lua_version` is `5.5`; `lua >= 5.4` dependencies are satisfied by the VM (`5.5-1 provided by VM`). |
| Project-local tree | Yes: `luarocks init --lua-versions=5.5 <name> <version>` creates `.luarocks/config-5.5.lua`, `lua_modules/`, and `./luarocks` and `./lua` wrappers. |
| Install into the tree | Yes: `./luarocks install --deps-only <rockspec>` installs into `lua_modules/` only. |
| Lockfile write | Only after the dependencies are installed: `./luarocks build --pin --only-deps <rockspec>` writes `luarocks.lock` (`dependencies = { [name] = "version" }`, plus the pseudo-rock `lua = "5.5-1"`). On a fresh tree it fails (`Could not satisfy dependency lua 5.5-1: ... provided by VM`, exit 1, no lockfile; seen on Ubuntu CI with `inspect` and locally). Workaround: `install --deps-only` first, then pin. |
| Lockfile read | Yes: with `luarocks.lock` present, a fresh tree gets `dep-a 1.0-1`; without it, `dep-a 1.1-1` (the newest). |
| Remote manifests | `luarocks.org` manifests are reachable (HTTP 200); `--only-server` with a 5.5 manifest works. Rocks published for 5.5 are scarce, so many need `--check-lua-versions`/`--lua-version` care. |

Caveats observed:

- With a lockfile present, LuaRocks prints `spk 1.0-1 is pinned to lua 5.5-1 (not
  installed)` and `--deps-only` returns exit code 1 when everything is already installed.
  The `lua` pseudo-rock in the lock is noise; treat the exit code with care in tooling.
- The lockfile only maps names to exact versions: no checksums, no sources, no
  per-platform data.

## Cross-platform results (CI)

| Step | Linux | macOS | Windows |
|---|---|---|---|
| `init`, project-local tree, `install --deps-only` (real rock `inspect` 3.1.3) | OK | OK | OK |
| `build --pin --only-deps` on a fresh tree | fails (see caveats) | fails | fails |
| `install --deps-only` then `build --pin --only-deps` | writes lock | writes lock | writes lock |
| Reinstall from lock with the `lua` entry removed | OK, exit 0 | OK, exit 0 | OK, exit 0 |
| Reinstall from lock as written | installs, error printed, exit 1 | same | same |
| C rock (`luafilesystem` 1.9.0) built and loaded | OK | OK | fails: `Failed finding the Lua library` |

Additional caveats:

- A `luarocks.lock` in the working directory applies to every `luarocks` command run
  there, including unrelated `install` commands. Run such commands from another
  directory (use `--tree`).
- Windows C rocks need `variables.LUA_LIBDIR` (and the import library name LuaRocks
  expects, e.g. `lua55.lib`) in the LuaRocks config. This is a property of how Lua is
  built, to be handled by the contributor bootstrap, not a Lua 5.5 incompatibility.

## Recommendation

1. Use LuaRocks 3.13+ with project-local trees as the dependency engine of `hecate.cli`.
2. `hecate.lock` can be a superset of `luarocks.lock`: the CLI keeps `luarocks.lock`
   (exact versions) as the machine-read source and adds its own file for extra data
   (checksums, toolchain). Do not change the `luarocks.lock` format.
3. Wrap LuaRocks in the CLI: install first, pin afterwards, strip the `lua` entry from
   the lock, run each command outside any directory holding a lock unless pinning is
   intended, and judge success by the installed set rather than the exit code alone.
4. The contributor bootstrap must configure `LUA_LIBDIR` and the library name on
   Windows (roadmap: contributor bootstrap).
5. Owner decision needed on 2.

## Remaining risks

- Only pure-Lua and one small C rock were tested; the real dependency set (luv,
  TLS, JSON) is covered by OQ-1, OQ-4 and OQ-5.
- LuaRocks behaviour around the `lua` pseudo-rock may change in later 3.x releases.
