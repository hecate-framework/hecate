-- Matching throughput against route tables of growing size: a static path, a path with two parameters, a wildcard, a
-- miss (404) and a method the path does not serve (405, with its `Allow` list); then a static match and a match with a
-- parameter under a prefix with a wide fan-out of static siblings. The rate of a static match must not fall as the
-- table grows (invariant of the package).
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

print(string.format("%-10s %14s %14s %14s %14s %14s", "routes", "static", "parameters", "wildcard", "miss", "405"))
for _, size in ipairs({ 10, 100, 1000, 10000 }) do
  local r = build(size)
  local static = rate(function() r:match("GET", "/api/v1/target") end)
  local parameters = rate(function() r:match("GET", "/api/v1/target/42/items/7") end)
  local wildcard = rate(function() r:match("GET", "/files/a/b/c/d.txt") end)
  local miss = rate(function() r:match("GET", "/api/v1/unknown/42") end)
  local refused = rate(function() r:match("DELETE", "/api/v1/target") end)
  print(string.format("%-10d %14.0f %14.0f %14.0f %14.0f %14.0f", size * 3 + 3, static, parameters, wildcard, miss, refused))
end

--- A table whose matched prefix `/api/v1/target/` has `width` static siblings next to the parameter.
local function fan_out(width)
  local list = {}
  for i = 1, width do list[#list + 1] = { method = "GET", path = ("/api/v1/target/child%d"):format(i) } end
  list[#list + 1] = { method = "GET", path = "/api/v1/target/{id}" }
  list[#list + 1] = { method = "GET", path = "/api/v1/target/last" }
  return router.Router(list)
end

print()
print(string.format("%-10s %14s %14s", "siblings", "static", "parameter"))
for _, width in ipairs({ 10, 100, 1000, 10000 }) do
  local r = fan_out(width)
  local static = rate(function() r:match("GET", "/api/v1/target/last") end)
  local parameter = rate(function() r:match("GET", "/api/v1/target/42") end)
  print(string.format("%-10d %14.0f %14.0f", width + 2, static, parameter))
end
