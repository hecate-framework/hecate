-- Wrapper of process_test.lua: arg[1] and arg[2] are package.path and package.cpath of the test
-- run, arg[3] is the value of `stdout` and `stderr` for the child it spawns. The child writes
-- "OUT" to its standard output and "ERR" to its standard error; the wrapper then writes "wrapper".
package.path, package.cpath = arg[1], arg[2]
local reactor = require("hecate.reactor")
local uv = require("luv")
reactor.run(function()
  local child = reactor.spawn(uv.exepath(), { "-e", "io.stdout:write('OUT'); io.stderr:write('ERR')" },
    { stdout = arg[3], stderr = arg[3] })
  child:wait()
end)
io.stdout:write("wrapper")
