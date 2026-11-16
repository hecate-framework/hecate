local M = {}
function M.run()
  return 1
end
-- coverage: off
function M.elsewhere()
  return 2
end
-- coverage: on
return M
