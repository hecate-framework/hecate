-- Runs a program to completion and captures its output. The program is the Lua
-- interpreter that runs this file (`arg[-1]`), so the example needs nothing
-- installed.
local reactor = require("hecate.reactor")

reactor.run(function()
  local result = reactor.run_process(arg[-1], { "-e", "io.write('hello'); os.exit(3)" })
  print(("%s, exit code %d"):format(result.stdout, result.code))
end)
-- Prints: hello, exit code 3
