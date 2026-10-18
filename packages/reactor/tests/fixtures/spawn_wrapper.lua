-- Wrapper of process_test.lua: arg[1] and arg[2] are package.path and package.cpath of the test
-- run, arg[3] is the value of `stdout` and `stderr` for the child it spawns ("default": none). The child writes
-- "OUT" to its standard output and "ERR" to its standard error; the wrapper then writes "wrapper".
package.path, package.cpath = arg[1], arg[2]
local reactor = require("hecate.reactor")
local uv = require("luv")
local value = arg[3] ~= "default" and arg[3] or nil
reactor.run(function()
  local child = reactor.spawn(uv.exepath(), { "-e", "io.stdout:write('OUT'); io.stderr:write('ERR')" },
    { stdout = value, stderr = value })
  child:wait()
end)
io.stdout:write("wrapper")
