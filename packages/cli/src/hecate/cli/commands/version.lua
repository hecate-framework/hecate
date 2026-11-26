-- `hecate version`: the versions of the framework and of what the executable embeds.
global <const> table, string

--- The `version` command.
---@type hecate.cli.Command
local command = {
  name = "version",
  summary = "Print the Hecate, Lua, LuaRocks and libuv versions and the platform",
  run = function(context)
    local runtime = context.runtime
    local parts = { "Lua " .. runtime.lua_version }
    if runtime.luarocks_version then parts[#parts + 1] = "LuaRocks " .. runtime.luarocks_version end
    if runtime.libuv_version then parts[#parts + 1] = "libuv " .. runtime.libuv_version end
    context.emit({
      hecate = runtime.hecate_version,
      lua = runtime.lua_version,
      luarocks = runtime.luarocks_version,
      libuv = runtime.libuv_version,
      platform = runtime.platform,
    }, string.format("Hecate %s (%s) — %s", runtime.hecate_version, table.concat(parts, ", "), runtime.platform))
    return 0
  end,
}

return command
