-- typecheck: lua-language-server --check with the repository .luarc.json; zero
-- diagnostics. Fails when the language server is not installed (see tools/bootstrap).
local util = require("lib.util")

return {
  description = "LuaLS --check with .luarc.json, zero diagnostics",
  run = function(ctx)
    local probe = util.is_windows() and "where lua-language-server 2>nul" or "command -v lua-language-server"
    local located, found = util.capture(probe)
    if not found then
      return { ok = false, problems = { "lua-language-server not found on PATH" } }
    end
    -- Launch by full path: on Windows LuaLS spawns a child from its own location.
    local exe = located:match("[^\r\n]+") or "lua-language-server"
    local out, ok = util.capture(("%s --check %s --configpath %s --checklevel=Warning 2>&1")
      :format(util.quote(exe), util.quote(ctx.root), util.quote(ctx.root .. "/.luarc.json")))
    if ok and (out:find("0 problems", 1, true) or out:find("no problems found", 1, true)) then return { ok = true, problems = {} } end
    return { ok = false, problems = { out } }
  end,
}
