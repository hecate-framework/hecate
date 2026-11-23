-- build-cli: builds the `hecate` executable: the C host with the Lua sources of the command-line interface embedded
-- and the native modules it needs linked in statically (luv with libuv, digest, the JSON codec) (ADR 0029).
-- Usage: build-cli [--output=<path>]   (default .hecate/build/cli/hecate)
-- Third-party sources (luv with its libuv, lua-digest) are cloned into `.hecate/build/cli/deps` at the versions pinned
-- below; a module whose build tool is missing (cmake, git, cargo) is left out and then found next to the executable or
-- in LUA_CPATH, which `hecate doctor` reports.
local util = require("lib.util")
local bundle = require("lib.cli_bundle")

local LUV = { url = "https://github.com/luvit/luv", tag = "1.53.0-0" } -- the version `ci.yml` installs
local DIGEST = { url = "https://github.com/osch/lua-digest", tag = "v0.0.1" }

local function find_lua(root)
  local candidates = { "/opt/lua-5.5", root .. "/.hecate/toolchain/lua" }
  table.insert(candidates, 1, os.getenv("LUA_DIR") or false)
  for _, dir in ipairs(candidates) do
    if dir and util.exists(dir .. "/include/lua.h") and util.exists(dir .. "/lib/liblua.a") then return dir end
  end
  return nil
end

--- Clones `spec` under `deps` once and returns its directory, or nil and the output of git.
local function fetch(deps, name, spec)
  local dir = deps .. "/" .. name
  if util.exists(dir) then return dir end
  local out, ok = util.capture(("git clone -q --depth 1 --branch %s --recurse-submodules --shallow-submodules %s %s 2>&1")
    :format(spec.tag, util.quote(spec.url), util.quote(dir)))
  if not ok then return nil, out end
  return dir
end

return {
  description = "build the hecate executable: C host with the CLI embedded and native modules linked (Linux and macOS)",
  run = function(ctx)
    if util.is_windows() then
      return { ok = false, problems = { "build-cli: Windows is not supported yet (planned: lua55.dll beside hecate.exe)" } }
    end
    local output = ctx.root .. "/.hecate/build/cli/hecate"
    for _, a in ipairs(ctx.args) do output = a:match("^%-%-output=(.+)$") or output end
    local lua = find_lua(ctx.root)
    if not lua then
      return { ok = false, problems = { "build-cli: no Lua 5.5 with include/lua.h and lib/liblua.a (set LUA_DIR)" } }
    end
    local dir = output:match("^(.*)/[^/]*$") or "."
    local deps = ctx.root .. "/.hecate/build/cli/deps"
    util.mkdir(dir)
    util.mkdir(deps)
    local generated = dir .. "/bundle.c"
    local f = assert(io.open(generated, "wb"))
    f:write(bundle.render(bundle.collect(ctx.root)))
    f:close()

    local host = ctx.root .. "/packages/cli/csrc"
    local linux = util.capture("uname -s") == "Linux"
    local cflags = "-std=c99 -O2 -I" .. util.quote(lua .. "/include")
    local strict = "-Wall -Wextra -Werror"
    local objects, defines, libraries, notes = {}, {}, { util.quote(lua .. "/lib/liblua.a") }, {}

    local function compile(source, extra, flags)
      local object = dir .. "/" .. source:match("([^/]+)%.c$") .. ".o"
      local out, ok = util.capture(("cc %s %s -c -o %s %s 2>&1"):format(flags or cflags, extra or "", util.quote(object), util.quote(source)))
      if not ok then return nil, out end
      objects[#objects + 1] = util.quote(object)
      return true
    end
    local function skip(what, why) notes[#notes + 1] = what .. " is not linked in: " .. why end

    -- luv and libuv (CMake builds libuv from the submodule).
    local luv_dir, why = fetch(deps, "luv", LUV)
    if not luv_dir then skip("luv", "cannot clone: " .. tostring(why))
    else
      local build = deps .. "/luv-build"
      if not util.exists(build .. "/libluv.a") then
        local _, have_cmake = util.capture("cmake --version")
        local out, ok
        if have_cmake then
          out, ok = util.capture(("cmake -S %s -B %s -DBUILD_MODULE=OFF -DBUILD_STATIC_LIBS=ON -DWITH_LUA_ENGINE=Lua -DLUA_BUILD_TYPE=System -DLUA_INCLUDE_DIR=%s -DLUA_LIBRARIES=%s -DWITH_SHARED_LIBUV=OFF -DCMAKE_BUILD_TYPE=Release 2>&1 && cmake --build %s -j4 2>&1")
            :format(util.quote(luv_dir), util.quote(build), util.quote(lua .. "/include"), util.quote(lua .. "/lib/liblua.a"), util.quote(build)))
        end
        if not have_cmake or not ok then skip("luv", have_cmake and ("cmake failed:\n" .. out) or "cmake not found") end
      end
      if util.exists(build .. "/libluv.a") then
        libraries[#libraries + 1] = util.quote(build .. "/libluv.a")
        libraries[#libraries + 1] = util.quote(build .. "/deps/libuv/libuv.a")
        defines[#defines + 1] = "-DHECATE_STATIC_LUV"
      end
    end

    -- digest (SHA-256 of `hecate.cli.digest`).
    local digest_dir, digest_why = fetch(deps, "lua-digest", DIGEST)
    if not digest_dir then skip("digest", "cannot clone: " .. tostring(digest_why))
    else
      -- digestlib.c includes md5.c and sha2.c; the version comes from the rockspec in a normal build.
      local ok1, e1 = compile(digest_dir .. "/digestlib.c", "-I" .. util.quote(digest_dir) .. " -DLUA_DIGEST_VERSION=" .. DIGEST.tag:sub(2))
      if ok1 then defines[#defines + 1] = "-DHECATE_STATIC_DIGEST"
      else return { ok = false, problems = { "build-cli: digest: " .. tostring(e1) } } end
    end

    -- hecate.json: the decoder (C over yyjson) and the encoder (Rust, linked as a static library).
    local json = ctx.root .. "/packages/json/csrc"
    local ok_native, e_native = compile(json .. "/native.c", "-I" .. util.quote(json))
    local ok_yyjson, e_yyjson = compile(json .. "/vendor/yyjson.c", "-I" .. util.quote(json))
    if not (ok_native and ok_yyjson) then return { ok = false, problems = { "build-cli: json decoder: " .. tostring(e_native or e_yyjson) } } end
    defines[#defines + 1] = "-DHECATE_STATIC_JSON_DECODER"
    local _, have_cargo = util.capture("cargo --version")
    if not have_cargo then skip("the JSON encoder", "cargo not found")
    else
      local rust = deps .. "/rust"
      local out, ok = util.capture(("cargo rustc --release --locked --lib --crate-type staticlib --manifest-path %s --target-dir %s 2>&1")
        :format(util.quote(ctx.root .. "/packages/json/native/Cargo.toml"), util.quote(rust)))
      if not ok then skip("the JSON encoder", "cargo failed:\n" .. out)
      else
        libraries[#libraries + 1] = util.quote(rust .. "/release/libhecate_json_encoder_native.a")
        defines[#defines + 1] = "-DHECATE_STATIC_JSON_ENCODER"
      end
    end

    local cmd = table.concat({
      "cc", cflags, strict, table.concat(defines, " "),
      "-I" .. util.quote(host),
      "-o", util.quote(output),
      util.quote(host .. "/hecate.c"), util.quote(generated), table.concat(objects, " "),
      table.concat(libraries, " "),
      linux and "-Wl,-E" or "-Wl,-export_dynamic", "-lm", "-lpthread", linux and "-ldl -lrt" or "",
      "2>&1",
    }, " ")
    local out, ok = util.capture(cmd)
    if not ok then return { ok = false, problems = { "build-cli: link failed:\n" .. out } } end
    for _, n in ipairs(notes) do io.stderr:write("build-cli: ", n, "\n") end
    return { ok = true, problems = {}, output = output, notes = notes }
  end,
}
