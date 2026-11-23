-- build-cli: builds the `hecate` executable (C host with the Lua sources of the command-line interface embedded).
-- Usage: build-cli [--output=<path>]   (default .hecate/build/cli/hecate)
local util = require("lib.util")
local bundle = require("lib.cli_bundle")

local function find_lua(root)
  local candidates = { os.getenv("LUA_DIR") }
  candidates[#candidates + 1] = "/opt/lua-5.5"
  candidates[#candidates + 1] = root .. "/.hecate/toolchain/lua"
  for _, dir in ipairs(candidates) do
    if dir and util.exists(dir .. "/include/lua.h") and util.exists(dir .. "/lib/liblua.a") then return dir end
  end
  return nil
end

return {
  description = "build the hecate executable: C host with the CLI embedded (Linux and macOS)",
  run = function(ctx)
    if util.is_windows() then
      return { ok = false, problems = { "build-cli: Windows is not supported yet (planned: lua55.dll beside hecate.exe)" } }
    end
    local output = ctx.root .. "/.hecate/build/cli/hecate"
    for _, a in ipairs(ctx.args) do
      output = a:match("^%-%-output=(.+)$") or output
    end
    local lua = find_lua(ctx.root)
    if not lua then
      return { ok = false, problems = { "build-cli: no Lua 5.5 with include/lua.h and lib/liblua.a (set LUA_DIR)" } }
    end
    local dir = output:match("^(.*)/[^/]*$") or "."
    util.mkdir(dir)
    local generated = dir .. "/bundle.c"
    local f = assert(io.open(generated, "wb"))
    f:write(bundle.render(bundle.collect(ctx.root)))
    f:close()
    local host = ctx.root .. "/packages/cli/csrc"
    local linux = util.capture("uname -s") == "Linux"
    local cmd = table.concat({
      "cc -std=c99 -O2 -Wall -Wextra -Werror",
      "-I" .. util.quote(lua .. "/include"), "-I" .. util.quote(host),
      "-o", util.quote(output),
      util.quote(host .. "/hecate.c"), util.quote(generated), util.quote(lua .. "/lib/liblua.a"),
      linux and "-Wl,-E" or "-Wl,-export_dynamic", "-lm", linux and "-ldl" or "",
      "2>&1",
    }, " ")
    local out, ok = util.capture(cmd)
    if not ok then return { ok = false, problems = { "build-cli: compilation failed:\n" .. out } } end
    return { ok = true, problems = {}, output = output }
  end,
}
