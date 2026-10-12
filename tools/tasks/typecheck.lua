-- typecheck: lua-language-server --check with the repository .luarc.json; zero
-- diagnostics. Fails when the language server is not installed (see tools/bootstrap).
local util = require("lib.util")

return {
  description = "LuaLS --check with .luarc.json, zero diagnostics",
  run = function(ctx)
    local probe = util.is_windows() and "where lua-language-server 2>nul" or "command -v lua-language-server"
    local _, found = util.capture(probe)
    if not found then
      return { ok = false, problems = { "lua-language-server not found on PATH" } }
    end
    local out, ok = util.capture(('lua-language-server --check "%s" --configpath "%s/.luarc.json" --checklevel=Warning 2>&1')
      :format(ctx.root, ctx.root))
    if ok and out:find("0 problems", 1, true) then return { ok = true, problems = {} } end
    return { ok = false, problems = { out } }
  end,
}
