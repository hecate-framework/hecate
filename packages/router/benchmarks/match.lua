-- Matching throughput against route tables of growing size: a static path, a path with two parameters, a wildcard and a
-- miss. The rate of a static match must not fall as the table grows (invariant of the package).
-- Usage: lua packages/router/benchmarks/match.lua   (from the repository root)
global <const> package, os, string, print, require, table, ipairs
package.path = "packages/router/src/?.lua;packages/router/src/?/init.lua;packages/core/src/?.lua;"
  .. "packages/core/src/?/init.lua;" .. package.path

local router = require("hecate.router")

local ROUNDS = 7
local SECONDS = 0.25 -- per sample

--- Operations per second: repeats `step` for SECONDS and divides, median of ROUNDS samples.
local function rate(step)
  local samples = {}
  step()
  for i = 1, ROUNDS do
    local count, start = 0, os.clock()
    repeat
      for _ = 1, 100 do step() end
      count = count + 100
    until os.clock() - start >= SECONDS
    samples[i] = count / (os.clock() - start)
  end
  table.sort(samples)
  return samples[(ROUNDS + 1) // 2]
end

local function build(size)
  local list = {}
  for i = 1, size do
    list[#list + 1] = { method = "GET", path = ("/api/v1/resource%d/{id}/items/{item}"):format(i) }
    list[#list + 1] = { method = "POST", path = ("/api/v1/resource%d"):format(i) }
    list[#list + 1] = { method = "GET", path = ("/static%d/{path...}"):format(i) }
  end
  list[#list + 1] = { method = "GET", path = "/api/v1/target" }
  list[#list + 1] = { method = "GET", path = "/api/v1/target/{id}/items/{item}" }
  list[#list + 1] = { method = "GET", path = "/files/{path...}" }
  return router.Router(list)
end

print(string.format("%-10s %14s %14s %14s %14s", "routes", "static", "parameters", "wildcard", "miss"))
for _, size in ipairs({ 10, 100, 1000, 10000 }) do
  local r = build(size)
  local static = rate(function() r:match("GET", "/api/v1/target") end)
  local parameters = rate(function() r:match("GET", "/api/v1/target/42/items/7") end)
  local wildcard = rate(function() r:match("GET", "/files/a/b/c/d.txt") end)
  local miss = rate(function() r:match("GET", "/api/v1/unknown/42") end)
  print(string.format("%-10d %14.0f %14.0f %14.0f %14.0f", size * 3 + 3, static, parameters, wildcard, miss))
end
