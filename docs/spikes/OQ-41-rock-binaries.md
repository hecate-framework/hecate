# OQ-41 (7): shipping the native module inside the rock

Question (owner, 2026-10-18): can the Rust native module of `net` ship inside the rock, so
that users need no Rust toolchain? Answer: **yes**, with LuaRocks binary rocks. Verified on
Linux x86_64 with LuaRocks 3.13 and Lua 5.5.1 (macOS and Windows: by release CI, not yet run).

## What was tested

A throwaway rock (`spikes/OQ-41/`, not committed) with a Lua module and a prebuilt
`tls_native.so`, declared through `build.install.lib`:

```lua
build = {
  type = "builtin",
  modules = { ["hecate.net"] = "src/hecate/net/init.lua" },
  install = { lib = { ["hecate.net.tls_native"] = "tls_native.so" } },
}
```

1. `luarocks make` installs the library at `lib/lua/5.5/hecate/net/tls_native.so`, the path
   `require("hecate.net.tls_native")` resolves.
2. `luarocks make --pack-binary-rock` produces `hecate-nettest-1.0-1.linux-x86_64.rock`.
3. A local server holding both the rockspec (source) and the binary rock, indexed with
   `luarocks-admin make_manifest`: `luarocks install --only-server` chose the **binary
   rock** (`Installing .../hecate-nettest-1.0-1.linux-x86_64.rock`), with no compiler involved.

## Consequences for the design

- Release CI builds the module on each platform, then packs one binary rock per platform
  and architecture (`linux-x86_64`, `linux-aarch64`, `macosx-x86_64`, `macosx-arm64`,
  `win32-x86_64`) with `luarocks make --pack-binary-rock`, and uploads them next to the
  source rock. Users on those platforms get TLS without Rust.
- The source rock stays the fallback: its rockspec builds the crate with `cargo` (a
  `command` build) and needs a Rust toolchain; an unsupported platform fails at that step with
  a clear message.
- The `rust-mlua` LuaRocks build type is not needed.
- The file extension of the module is platform specific (`.so` on Linux and macOS, `.dll` on
  Windows); the release task passes the right file per platform.
- Publishing remains the owner's gate; `release-manager` implements the packing in
  `release.yml` (roadmap, Phase 3 release automation).
