-- build-native [package]: builds the Rust native modules of a package (default: net; ADR 0021)
-- with cargo and installs them in the project-local tree `.hecate/rocks`, where the test
-- harness and the bootstrap look for native modules. Needs a Rust toolchain.
--
-- Windows: mlua-sys needs the Lua 5.5 import library; set LUA_LIB_NAME (for example lua55),
-- LUA_LIB and LUA_INC before running (TLS spike OQ-4). macOS link flags are
-- set by this task (and mirrored in packages/net/native/.cargo/config.toml).
local util = require("lib.util")

-- package -> { crate directory, cargo library name, installed module path (without extension) }
local modules = {
  net = { dir = "native", lib = "hecate_net_tls_native", target = "hecate/net/tls_native" },
}

return {
  description = "build the Rust native modules of a package (cargo) into .hecate/rocks",
  run = function(ctx)
    local name = ctx.args[1] or "net"
    local m = modules[name]
    if not m then return { ok = false, problems = { "no native module for package '" .. name .. "'" } } end
    local crate = ("%s/packages/%s/%s"):format(ctx.root, name, m.dir)
    local _, have_cargo = util.capture("cargo --version")
    if not have_cargo then return { ok = false, problems = { "cargo not found: install a Rust toolchain" } } end
    local windows, macos = util.is_windows(), false
    if not windows then macos = util.capture("uname -s") == "Darwin" end
    -- Cargo reads `.cargo/config.toml` from the working directory, not from the manifest's,
    -- so the macOS link flags are passed through the environment as well.
    local env = macos and "RUSTFLAGS='-C link-arg=-undefined -C link-arg=dynamic_lookup' " or ""
    local out, ok = util.capture(("%scargo build --release --locked --manifest-path %s 2>&1"):format(
      env, util.quote(crate .. "/Cargo.toml")))
    if not ok then return { ok = false, problems = { "cargo build failed:\n" .. out } } end
    local built = ("%s/target/release/%s%s.%s"):format(crate, windows and "" or "lib", m.lib,
      windows and "dll" or macos and "dylib" or "so")
    local version = _VERSION:match("%d+%.%d+")
    local dest = ("%s/.hecate/rocks/lib/lua/%s/%s.%s"):format(ctx.root, version, m.target, windows and "dll" or "so")
    util.mkdir(dest:match("^(.*)/[^/]*$"))
    local cp = windows and 'copy /Y "%s" "%s" >NUL' or "cp '%s' '%s'"
    if windows then
      built = built:gsub("/", "\\")
      dest = dest:gsub("/", "\\")
    end
    local _, copied = util.capture(cp:format(built, dest))
    if not copied then return { ok = false, problems = { ("cannot copy %s to %s"):format(built, dest) } } end
    return { ok = true, problems = {}, output = "installed " .. dest }
  end,
}
