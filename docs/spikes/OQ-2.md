# Spike OQ-2: LuaRocks on Lua 5.5

Status: **partial**. Linux verified; macOS and Windows not yet verified. Recommendation
submitted to the owner.

## Question

Does LuaRocks 3.x support Lua 5.5 with project-local trees and lockfiles, and can
`hecate.lock` be a superset of `luarocks.lock`? (OQ-2)

## Method

LuaRocks 3.13.0 with Lua 5.5.1 (`/opt/lua-5.5`) on Linux x86_64, all work under
`spikes/OQ-2/`. The cloud network policy blocks GitHub source archives
(`github.com/*/archive/*` and `codeload.github.com` return 403), so rocks hosted on
GitHub (e.g. `inspect`) cannot be installed in cloud sessions. Dependencies were
therefore served from a local `file://` repository built with `luarocks-admin
make_manifest` (two versions of a pure-Lua rock, `dep-a` 1.0 and 1.1).

## Findings (Linux)

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

## Recommendation

1. Use LuaRocks 3.13+ with project-local trees as the dependency engine of `hecate.cli`.
2. `hecate.lock` can be a superset of `luarocks.lock` in the sense that the CLI keeps
   `luarocks.lock` (exact versions) as the machine-read source and adds its own file
   for extra data (checksums, toolchain). Do not change the `luarocks.lock` format.
3. Ignore the `lua` entry and the exit code 1 quirk in the CLI wrapper (read the
   resulting installed set instead).
4. Owner decision needed on 2.

## Remaining risks

- macOS and Windows not verified (needs a CI workflow that builds Lua 5.5, as in OQ-1).
- GitHub source archives are blocked in cloud sessions: add `github.com` archive
  downloads (`codeload.github.com`) to the network allowlist to test real rocks.
