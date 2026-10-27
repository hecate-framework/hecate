-- Spread of connections over workers: the largest count divided by the smallest (1.00 is perfect balance,
global <const> ipairs, math
-- the figure of ADR 0023). A worker that took nothing makes the ratio infinite; it is reported as the largest count.
local M = {}

--- Largest to smallest number of accepted connections.
---@param counts integer[]  connections accepted by each worker
---@return number ratio  `0` when there is no worker or no connection at all
function M.ratio(counts)
  if #counts == 0 then return 0 end
  local lowest, highest = counts[1], counts[1]
  for _, count in ipairs(counts) do
    lowest, highest = math.min(lowest, count), math.max(highest, count)
  end
  if highest == 0 then return 0 end
  return lowest == 0 and highest or highest / lowest
end

return M
