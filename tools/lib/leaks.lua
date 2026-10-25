-- Helpers of the `leaks` task: which suites are reactor-heavy and how the leak check is switched on.
local M = {}

--- Packages whose suites open libuv handles and coroutines (default selection of the task).
M.packages = { "reactor", "net" }

--- Environment prefix that enables the harness leak check for a command.
---@param windows boolean
---@return string
function M.environment(windows)
  return windows and "set HECATE_TEST_LEAKS=1&& " or "HECATE_TEST_LEAKS=1 "
end

return M
