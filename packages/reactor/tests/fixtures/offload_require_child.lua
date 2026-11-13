-- Child of offload_exit_test.lua, started with `LUA_PATH` naming the fixtures directory: an offloaded
-- function requires a module on its pool thread, whose Lua state takes its search path from
-- `LUA_PATH` (concurrency.md, "Offload"). Exits with 0 when the module was found and loaded there.
local reactor = require("hecate.reactor")
local answer, loaded_here = reactor.run(function()
  return reactor.offload(function(name) return require(name).answer, package.loaded[name] ~= nil end,
    "offload_require_module")
end)
io.stderr:write(("answer %s, loaded on the pool thread %s\n"):format(tostring(answer), tostring(loaded_here)))
os.exit(answer == 42 and loaded_here == true and package.loaded.offload_require_module == nil and 0 or 1)
