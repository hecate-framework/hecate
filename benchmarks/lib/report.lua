-- How a scenario process tells the runner what it has to say (`listening <port>`, `label value unit` lines).
-- Started by benchmarks/lib/runner.lua with a message pipe, a process sends its text over it (reactor.spawn cannot
-- capture standard output); started by hand, it prints. Call from inside `reactor.run`.
local reactor = require("hecate.reactor")

local M = {}

--- Reports `text` to the runner, or prints it when there is no runner.
---@param text string
function M.send(text)
  local peer = reactor.ipc.parent()
  if peer then
    peer:send(text)
  else
    io.stdout:write(text, "\n")
    io.stdout:flush()
  end
end

return M
