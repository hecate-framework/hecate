-- build-cli: builds the `hecate` executable: the C host with the Lua sources of the command-line interface embedded,
-- the native modules it needs linked in statically (luv with libuv, digest, luafilesystem, the JSON codec) and LuaRocks
-- embedded (ADR 0029).
-- Usage: build-cli [--output=<path>]   (default .hecate/build/cli/hecate, hecate.exe on Windows)
-- Third-party sources (luv with its libuv, lua-digest, luafilesystem, LuaRocks) are cloned into
-- `.hecate/build/cli/deps` at the versions pinned below. A module whose build tool is missing (cmake, cargo) is left
-- out and then found next to the executable or in LUA_CPATH; `hecate doctor` reports what is missing.
-- Unix: `cc` and the static Lua (`lib/liblua.a`). Windows: MSVC (`cl`, from a Developer Command Prompt) and the
-- shared Lua of the bootstrap (`lib/lua55.lib`, `bin/lua55.dll`, copied beside `hecate.exe`).
local util = require("lib.util")
local bundle = require("lib.cli_bundle")

local LUV = { url = "https://github.com/luvit/luv", tag = "1.53.0-0" } -- the version `ci.yml` installs
local LUAROCKS = { url = "https://github.com/luarocks/luarocks", tag = "v3.13.0" }
local LFS = { url = "https://github.com/lunarmodules/luafilesystem", tag = "v1_9_0" }
local DIGEST = { url = "https://github.com/osch/lua-digest", tag = "v0.0.1" }

local windows = util.is_windows()

--- The Lua to build against: its directory, and the library to link (static on Unix, the import library on Windows).
---@return string? directory
---@return string? library
local function find_lua(root)
  local candidates = { "/opt/lua-5.5", root .. "/.hecate/toolchain/lua", root .. "/.hecate/toolchain" }
  table.insert(candidates, 1, os.getenv("LUA_DIR") or false)
  local library = windows and "/lib/lua55.lib" or "/lib/liblua.a"
  for _, dir in ipairs(candidates) do
    if dir and util.exists(dir .. "/include/lua.h") and util.exists(dir .. library) then return dir, dir .. library end
  end
  return nil
end

--- Quotes a URL for the shell (`util.quote` turns the slashes of a path into backslashes on Windows).
local function quote_url(url) return windows and ('"' .. url .. '"') or util.quote(url) end

--- Clones `spec` under `deps` once and returns its directory, or nil and the output of git.
local function fetch(deps, name, spec)
  local dir = deps .. "/" .. name
  if util.exists(dir) then return dir end
  local out, ok = util.capture(("git clone -q --depth 1 --branch %s --recurse-submodules --shallow-submodules %s %s 2>&1")
    :format(spec.tag, quote_url(spec.url), util.quote(dir)))
  if not ok then return nil, out end
  return dir
end

--- The first file under `dir` (recursively) whose name matches `pattern` (a Lua pattern on the file name).
local function find_file(dir, pattern)
  for _, suffix in ipairs({ ".a", ".lib" }) do
    for _, path in ipairs(util.walk(dir, suffix)) do
      if path:match("([^/\\]+)$"):match(pattern) then return path end
    end
  end
  return nil
end

-- System libraries that libuv and the Rust runtime need on Windows.
local WINDOWS_LIBRARIES = "ws2_32.lib iphlpapi.lib userenv.lib psapi.lib advapi32.lib ntdll.lib dbghelp.lib"
  .. " shell32.lib ole32.lib user32.lib bcrypt.lib kernel32.lib"

return {
  description = "build the hecate executable: C host, CLI and LuaRocks embedded, native modules linked (Linux, macOS, Windows)",
  run = function(ctx)
    local output = ctx.root .. "/.hecate/build/cli/hecate" .. (windows and ".exe" or "")
    for _, a in ipairs(ctx.args) do output = a:match("^%-%-output=(.+)$") or output end
    local lua, lua_library = find_lua(ctx.root)
    if not lua or not lua_library then
      return { ok = false, problems = { "build-cli: no Lua 5.5 with include/lua.h and " .. (windows and "lib/lua55.lib" or "lib/liblua.a") .. " (set LUA_DIR)" } }
    end
    local dir = output:match("^(.*)/[^/]*$") or "."
    local deps = ctx.root .. "/.hecate/build/cli/deps"
    util.mkdir(dir)
    util.mkdir(deps)
    local generated = dir .. "/bundle.c"
    local modules = bundle.collect(ctx.root)

    local host = ctx.root .. "/packages/cli/csrc"
    local linux = not windows and util.capture("uname -s") == "Linux"
    local objects, defines, libraries, notes = {}, {}, { util.quote(lua_library) }, {}
    local object_suffix = windows and ".obj" or ".o"

    --- Compiles one C file into an object of `dir`; `extra` are include and define options, `strict` adds the
    --- warnings-as-errors of the repository's own sources.
    local function compile(source, extra, strict)
      local object = dir .. "/" .. source:match("([^/]+)%.c$") .. object_suffix
      local cmd
      if windows then
        local defs = {}
        for _, d in ipairs(defines) do defs[#defs + 1] = (d:gsub("^%-D", "/D")) end
        cmd = ("cl /nologo /O2 /MD /TC /W3 /D_CRT_SECURE_NO_WARNINGS /I%s %s %s /c /Fo%s %s 2>&1"):format(
          util.quote(lua .. "/include"), table.concat(defs, " "), (extra or ""):gsub("%-I", "/I"):gsub("%-D", "/D"),
          util.quote(object), util.quote(source))
      else
        cmd = ("cc -std=c99 -O2 %s -I%s %s %s -c -o %s %s 2>&1"):format(strict and "-Wall -Wextra -Werror" or "",
          util.quote(lua .. "/include"), table.concat(defines, " "), extra or "", util.quote(object), util.quote(source))
      end
      local out, ok = util.capture(cmd)
      if not ok then return nil, out end
      objects[#objects + 1] = util.quote(object)
      return true
    end
    local function skip(what, why) notes[#notes + 1] = what .. " is not linked in: " .. why end
    local function fail(what, why) return { ok = false, problems = { "build-cli: " .. what .. ": " .. tostring(why) } } end

    -- luv and libuv (CMake builds libuv from the submodule).
    local luv_dir, why = fetch(deps, "luv", LUV)
    if not luv_dir then skip("luv", "cannot clone: " .. tostring(why))
    else
      local build = deps .. "/luv-build"
      local function built() return find_file(build, "^libluv[_a]*%.%a+$") or find_file(build, "^luv%.lib$") end
      if not built() then
        local _, have_cmake = util.capture("cmake --version")
        local out, ok
        if have_cmake then
          out, ok = util.capture(("cmake -S %s -B %s -DBUILD_MODULE=OFF -DBUILD_STATIC_LIBS=ON -DWITH_LUA_ENGINE=Lua -DLUA_BUILD_TYPE=System -DLUA_INCLUDE_DIR=%s -DLUA_LIBRARIES=%s -DWITH_SHARED_LIBUV=OFF -DCMAKE_BUILD_TYPE=Release 2>&1 && cmake --build %s --config Release -j4 2>&1")
            :format(util.quote(luv_dir), util.quote(build), util.quote(lua .. "/include"), util.quote(lua_library), util.quote(build)))
        end
        if not have_cmake or not ok then skip("luv", have_cmake and ("cmake failed:\n" .. out) or "cmake not found") end
      end
      local luv_library = built()
      local uv_library = find_file(build .. "/deps/libuv", "^libuv%.%a+$") or find_file(build .. "/deps/libuv", "^uv_a%.lib$")
        or find_file(build .. "/deps/libuv", "^libuv_a%.%a+$")
      if luv_library and uv_library then
        libraries[#libraries + 1] = util.quote(luv_library)
        libraries[#libraries + 1] = util.quote(uv_library)
        defines[#defines + 1] = "-DHECATE_STATIC_LUV"
      elseif not notes[#notes] then
        skip("luv", "the static libraries were not found in " .. build)
      end
    end

    -- LuaRocks (Lua sources embedded, run by `hecate --luarocks`) and luafilesystem, which it requires.
    local luarocks_dir, luarocks_why = fetch(deps, "luarocks", LUAROCKS)
    if not luarocks_dir then skip("LuaRocks", "cannot clone: " .. tostring(luarocks_why))
    else
      for _, m in ipairs(bundle.collect_luarocks(luarocks_dir)) do modules[#modules + 1] = m end
      defines[#defines + 1] = "-DHECATE_EMBEDDED_LUAROCKS"
    end
    local lfs_dir, lfs_why = fetch(deps, "luafilesystem", LFS)
    if not lfs_dir then skip("luafilesystem", "cannot clone: " .. tostring(lfs_why))
    else
      local ok, err = compile(lfs_dir .. "/src/lfs.c", "-D_GNU_SOURCE -I" .. util.quote(lfs_dir .. "/src"))
      if not ok then return fail("luafilesystem", err) end
      defines[#defines + 1] = "-DHECATE_STATIC_LFS"
    end

    local f = assert(io.open(generated, "wb"))
    f:write(bundle.render(modules))
    f:close()

    -- digest (SHA-256 of `hecate.cli.digest`); digestlib.c includes md5.c and sha2.c, the version comes from the rockspec
    -- in a normal build.
    local digest_dir, digest_why = fetch(deps, "lua-digest", DIGEST)
    if not digest_dir then skip("digest", "cannot clone: " .. tostring(digest_why))
    else
      local ok, err = compile(digest_dir .. "/digestlib.c", "-I" .. util.quote(digest_dir) .. " -DLUA_DIGEST_VERSION=" .. DIGEST.tag:sub(2))
      if not ok then return fail("digest", err) end
      defines[#defines + 1] = "-DHECATE_STATIC_DIGEST"
    end

    -- hecate.json: the decoder (C over yyjson) and the encoder (Rust, linked as a static library).
    local json = ctx.root .. "/packages/json/csrc"
    local ok_native, e_native = compile(json .. "/native.c", "-I" .. util.quote(json))
    local ok_yyjson, e_yyjson = compile(json .. "/vendor/yyjson.c", "-I" .. util.quote(json))
    if not (ok_native and ok_yyjson) then return fail("json decoder", e_native or e_yyjson) end
    defines[#defines + 1] = "-DHECATE_STATIC_JSON_DECODER"
    local _, have_cargo = util.capture("cargo --version")
    if not have_cargo then skip("the JSON encoder", "cargo not found")
    else
      local rust = deps .. "/rust"
      local out, ok = util.capture(("cargo rustc --release --locked --lib --crate-type staticlib --manifest-path %s --target-dir %s 2>&1")
        :format(util.quote(ctx.root .. "/packages/json/native/Cargo.toml"), util.quote(rust)))
      local library = rust .. "/release/" .. (windows and "hecate_json_encoder_native.lib" or "libhecate_json_encoder_native.a")
      if not ok or not util.exists(library) then skip("the JSON encoder", "cargo failed:\n" .. out)
      else
        libraries[#libraries + 1] = util.quote(library)
        defines[#defines + 1] = "-DHECATE_STATIC_JSON_ENCODER"
      end
    end

    -- The host and the link.
    local ok_host, e_host = compile(host .. "/hecate.c", "-I" .. util.quote(host), true)
    if not ok_host then return fail("host", e_host) end
    local ok_bundle, e_bundle = compile(generated, "-I" .. util.quote(host))
    if not ok_bundle then return fail("bundle", e_bundle) end
    local cmd
    if windows then
      -- Through `cl`, which drives the linker: a bare `link` may be the coreutils one that Git for Windows puts first.
      cmd = ("cl /nologo /Fe%s %s %s /link %s 2>&1"):format(util.quote(output), table.concat(objects, " "),
        table.concat(libraries, " "), WINDOWS_LIBRARIES)
    else
      cmd = table.concat({
        "cc", "-o", util.quote(output), table.concat(objects, " "), table.concat(libraries, " "),
        linux and "-Wl,-E" or "-Wl,-export_dynamic", "-lm", "-lpthread", linux and "-ldl -lrt" or "", "2>&1",
      }, " ")
    end
    local out, ok = util.capture(cmd)
    if not ok then return fail("link", out) end
    if windows then -- the shared Lua sits beside the executable
      local _, copied = util.capture(('copy /Y "%s" "%s" >NUL'):format((lua .. "/bin/lua55.dll"):gsub("/", "\\"), (dir .. "/lua55.dll"):gsub("/", "\\")))
      if not copied then return fail("lua55.dll", "cannot copy " .. lua .. "/bin/lua55.dll") end
    end
    for _, n in ipairs(notes) do io.stderr:write("build-cli: ", n, "\n") end
    return { ok = true, problems = {}, output = output, notes = notes }
  end,
}
