-- Route coverage: which routes of an application the requests of a test reached (testing.md, "Contract conformance").
global <const> require, table, ipairs, pairs, tostring, string

local core = require("hecate.core")

--- Records the routes (by name) that served a request and reports those never exercised. `hecate.test.boot`
--- creates one for each application it boots.
---@class hecate.test.RouteCoverage
---@overload fun(names: string[]): hecate.test.RouteCoverage
local RouteCoverage = core.class("RouteCoverage")

--- Creates a coverage of the routes `names`.
---@param names string[]  the route names of the application
function RouteCoverage:init(names)
  self._names, self._hit = {}, {}
  for _, name in ipairs(names) do self._names[#self._names + 1] = name end
  table.sort(self._names)
end

--- Records that the route `name` served a request. A name that is not a route of the application is ignored.
---@param name string
function RouteCoverage:record(name) self._hit[name] = true end

--- The names of the routes that served at least one request, sorted.
---@return string[] names
function RouteCoverage:exercised()
  local out = {}
  for _, name in ipairs(self._names) do if self._hit[name] then out[#out + 1] = name end end
  return out
end

--- The names of the routes that served no request, sorted.
---@return string[] names
function RouteCoverage:missed()
  local out = {}
  for _, name in ipairs(self._names) do if not self._hit[name] then out[#out + 1] = name end end
  return out
end

--- A short report: how many routes were exercised, and the names of those that were not.
---@return string report
function RouteCoverage:report()
  local missed = self:missed()
  local text = ("%d of %d routes exercised"):format(#self._names - #missed, #self._names)
  if #missed > 0 then text = text .. "\nnot exercised: " .. table.concat(missed, ", ") end
  return text
end

return core.finalise(RouteCoverage)
