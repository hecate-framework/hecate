-- build-native [package]: builds the native modules of a package (default: net) and installs them in
-- the project-local tree `.hecate/rocks`, where the test harness and the bootstrap look for native
-- modules. `net` is Rust (ADR 0021, needs a Rust toolchain); `json` is both: C (ADR 0020: yyjson
-- binding, needs a C compiler and the Lua headers: LUA_INC, or next to the interpreter, or /usr/include)
-- and Rust (ADR 0021: the encoder); `doc` is Rust (ADR 0022: comrak and syntect).
--
-- Windows: mlua-sys and the C modules need the Lua 5.5 import library; set LUA_LIB_NAME (for example lua55),
-- LUA_LIB and LUA_INC before running (TLS spike OQ-4). macOS link flags are
-- set by this task (and mirrored in packages/net/native/.cargo/config.toml).
local util = require("lib.util")
local sanitize = require("lib.sanitize")

-- package -> { crate directory, cargo library name, installed module path (without extension) }
local modules = {
  net = { dir = "native", lib = "hecate_net_tls_native", target = "hecate/net/tls_native" },
  json = { dir = "native", lib = "hecate_json_encoder_native", target = "hecate/json/encoder_native" },
  doc = { dir = "native", lib = "hecate_doc_native", target = "hecate/doc/native" },
}

-- C modules: package -> { sources (relative to the package), installed module path }
local c_modules = {
  json = { sources = { "csrc/native.c", "csrc/vendor/yyjson.c" }, target = "hecate/json/native" },
}

local function lua_include_dir(ctx)
  local candidates = { os.getenv("LUA_INC"), os.getenv("LUA_INCDIR") }
  local exe = util.interpreter():gsub("\\", "/")
  if not exe:find("/", 1, true) and not util.is_windows() then
    exe = util.capture("command -v " .. util.quote(exe)):gsub("%s+$", "")
  end
  local resolved = not util.is_windows() and util.capture("readlink -f " .. util.quote(exe)):gsub("%s+$", "") or ""
  for _, path in ipairs({ exe, resolved }) do
    local bin = path:match("^(.*)/[^/]*$")
    if bin then candidates[#candidates + 1] = bin .. "/../include" end
  end
  local version = _VERSION:match("%d+%.%d+")
  for _, dir in ipairs({ "/usr/local/include", "/usr/include/lua" .. version, "/usr/include" }) do
    candidates[#candidates + 1] = dir
  end
  for _, dir in ipairs(candidates) do
    if dir ~= "" and util.exists(dir .. "/lua.h") then return dir end
  end
  return nil
end

-- Windows: the MSVC compiler (`cl`, `link`) from the environment of the Developer Command Prompt, the Lua headers
-- and the import library of the interpreter's DLL (LUA_INC, LUA_LIB and LUA_LIB_NAME as for Rust, default: the
-- bootstrapped toolchain, `.hecate/toolchain`). /W4 /WX on our own sources, the vendored sources without warnings.
local function build_c_windows(ctx, name, m)
  local toolchain = ctx.root .. "/.hecate/toolchain"
  local include = os.getenv("LUA_INC") or (toolchain .. "/include")
  local libdir = os.getenv("LUA_LIB") or (toolchain .. "/lib")
  local libname = os.getenv("LUA_LIB_NAME") or "lua55"
  local version = _VERSION:match("%d+%.%d+")
  local dest = ("%s/.hecate/rocks/lib/lua/%s/%s.dll"):format(ctx.root, version, m.target)
  util.mkdir(dest:match("^(.*)/[^/]*$"))
  local package_dir = ("%s/packages/%s"):format(ctx.root, name)
  local build_dir = ("%s/.hecate/build/%s"):format(ctx.root, name)
  util.mkdir(build_dir)
  local objects = {}
  for index, source in ipairs(m.sources) do
    local own = not source:find("/vendor/", 1, true)
    local object = ("%s/%d.obj"):format(build_dir, index):gsub("/", "\\")
    local flags = own and "/O2 /std:c11 /W4 /WX" or "/O2 /std:c11 /w"
    local out, ok = util.capture(('cl /nologo /c %s /DLUA_BUILD_AS_DLL /I"%s" /Fo"%s" "%s" 2>&1'):format(
      flags, include:gsub("/", "\\"), object, (package_dir .. "/" .. source):gsub("/", "\\")))
    if not ok then return { ok = false, problems = { "compile failed for " .. source .. ":\n" .. out } } end
    objects[#objects + 1] = '"' .. object .. '"'
  end
  local out, ok = util.capture(('link /nologo /DLL /OUT:"%s" /EXPORT:luaopen_%s /LIBPATH:"%s" %s.lib %s 2>&1'):format(
    dest:gsub("/", "\\"), m.target:gsub("/", "_"), libdir:gsub("/", "\\"), libname, table.concat(objects, " ")))
  if not ok then return { ok = false, problems = { "link failed:\n" .. out } } end
  return { ok = true, problems = {}, output = "installed " .. dest }
end

-- Builds a C module with the system compiler: -Wall -Wextra -Werror on our own sources (coding-standards.md,
-- "C code"), the vendored sources unchanged and without those flags. Windows builds go through LuaRocks.
local function build_c(ctx, name, m)
  if util.is_windows() then return build_c_windows(ctx, name, m) end
  local include = lua_include_dir(ctx)
  if not include then return { ok = false, problems = { "lua.h not found: set LUA_INC to the Lua include directory" } } end
  local cc = os.getenv("CC") or "cc"
  local sanitized = os.getenv("HECATE_SANITIZE") == "1"
  local macos = util.capture("uname -s") == "Darwin"
  local version = _VERSION:match("%d+%.%d+")
  local dest = ("%s/.hecate/rocks/lib/lua/%s/%s.so"):format(ctx.root, version, m.target)
  util.mkdir(dest:match("^(.*)/[^/]*$"))
  local objects = {}
  local package_dir = ("%s/packages/%s"):format(ctx.root, name)
  local build_dir = ("%s/.hecate/build/%s"):format(ctx.root, name)
  util.mkdir(build_dir)
  for index, source in ipairs(m.sources) do
    local own = not source:find("/vendor/", 1, true)
    local object = ("%s/%d.o"):format(build_dir, index)
    local flags = own and "-std=c11 -O2 -Wall -Wextra -Werror" or "-O2 -w"
    if sanitized then flags = flags .. " " .. sanitize.cflags() end
    local out, ok = util.capture(("%s -c -fPIC %s -I%s %s -o %s 2>&1"):format(
      cc, flags, util.quote(include), util.quote(package_dir .. "/" .. source), util.quote(object)))
    if not ok then return { ok = false, problems = { "compile failed for " .. source .. ":\n" .. out } } end
    objects[#objects + 1] = util.quote(object)
  end
  local link = macos and "-bundle -undefined dynamic_lookup" or "-shared"
  if sanitized then link = link .. " -fsanitize=address,undefined" end
  local out, ok = util.capture(("%s %s -o %s %s -lm 2>&1"):format(cc, link, util.quote(dest), table.concat(objects, " ")))
  if not ok then return { ok = false, problems = { "link failed:\n" .. out } } end
  return { ok = true, problems = {}, output = "installed " .. dest }
end

local function build_rust(ctx, name, m)
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
end

return {
  description = "build the native modules of a package (cargo or cc) into .hecate/rocks",
  run = function(ctx)
    local name = ctx.args[1] or "net"
    local c, rust = c_modules[name], modules[name]
    if not c and not rust then return { ok = false, problems = { "no native module for package '" .. name .. "'" } } end
    local result = { ok = true, problems = {} }
    if c then
      result = build_c(ctx, name, c)
      if not result.ok then return result end
    end
    if rust then
      local built = build_rust(ctx, name, rust)
      if c and built.ok then built.output = result.output .. "\n" .. built.output end
      return built
    end
    return result
  end,
}
