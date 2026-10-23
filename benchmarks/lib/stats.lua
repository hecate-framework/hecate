-- Statistics of the benchmark harness: percentiles and the Mann-Whitney U test used by the A/B comparison
-- (benchmarks/README.md). Pure Lua, no dependency.
local M = {}

--- Percentile by the nearest-rank method.
---@param sorted number[]  values in ascending order, not empty
---@param p number  0 < p <= 100
---@return number
function M.percentile(sorted, p)
  local rank = math.ceil(p * #sorted / 100 - 1e-9) -- the epsilon absorbs float error
  if rank < 1 then rank = 1 end
  return sorted[rank]
end

--- Median of an unsorted array.
---@param values number[]
---@return number
function M.median(values)
  local sorted = { table.unpack(values) }
  table.sort(sorted)
  local n = #sorted
  if n % 2 == 1 then return sorted[(n + 1) // 2] end
  return (sorted[n // 2] + sorted[n // 2 + 1]) / 2
end

--- Standard normal survival function (Abramowitz and Stegun 7.1.26 on erfc).
local function normal_tail(z)
  local x = math.abs(z) / math.sqrt(2)
  local t = 1 / (1 + 0.3275911 * x)
  local poly = t * (0.254829592 + t * (-0.284496736 + t * (1.421413741 + t * (-1.453152027 + t * 1.061405429))))
  local erfc = poly * math.exp(-x * x)
  return erfc / 2
end

--- Two-sided Mann-Whitney U test, normal approximation with tie correction and continuity correction.
---@param a number[]
---@param b number[]
---@return number u  the U statistic of `a`
---@return number p  the two-sided p-value
function M.mann_whitney(a, b)
  local n1, n2 = #a, #b
  local all = {}
  for _, v in ipairs(a) do all[#all + 1] = { v, 1 } end
  for _, v in ipairs(b) do all[#all + 1] = { v, 2 } end
  table.sort(all, function(x, y) return x[1] < y[1] end)
  local n = #all
  local rank_sum_a, tie_term = 0, 0
  local i = 1
  while i <= n do
    local j = i
    while j < n and all[j + 1][1] == all[i][1] do j = j + 1 end
    local rank = (i + j) / 2
    for k = i, j do
      if all[k][2] == 1 then rank_sum_a = rank_sum_a + rank end
    end
    local ties = j - i + 1
    tie_term = tie_term + (ties ^ 3 - ties)
    i = j + 1
  end
  local u = rank_sum_a - n1 * (n1 + 1) / 2
  local mean = n1 * n2 / 2
  local variance = n1 * n2 / 12 * ((n + 1) - tie_term / (n * (n - 1)))
  if variance <= 0 then return u, 1 end
  local z = (math.abs(u - mean) - 0.5) / math.sqrt(variance)
  if z < 0 then z = 0 end
  return u, math.min(1, 2 * normal_tail(z))
end

return M
