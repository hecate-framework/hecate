-- The order of the filter chain: the filters of the application, of the
-- feature module, of the controller, then of the route, outermost first.
-- Each filter sees the request on the way in and the result on the way out.
local core = require("hecate.core")
local http = require("hecate.http")
local hecate = require("hecate")

-- A filter is any table with a `handle(self, request, next)` function.
local trail = {}
local function trace(name)
  return {
    handle = function(_, request, next)
      trail[#trail + 1] = name
      local result = next(request)
      trail[#trail + 1] = "/" .. name
      return result
    end,
  }
end

local Reports = core.class("Reports", hecate.Controller)
Reports.prefix = "/reports"
Reports.filters = { trace("controller") }
hecate.Controller.route(Reports, {
  method = "GET", path = "/daily", action = "daily",
  filters = { trace("route") },
})
function Reports:daily()
  trail[#trail + 1] = "action"
  return { total = 42 }
end
core.finalise(Reports)

local app = hecate.Application({
  filters = { trace("global") },
  modules = {
    { name = "reporting", routes = { Reports }, filters = { trace("module") } },
  },
})
local serve = app:boot()

local function get(target)
  trail = {}
  local request = http.Request({
    method = "GET", target = target, fields = http.Fields(),
  })
  return serve(request).status
end

print(get("/reports/daily"))
-- Prints: 200
print(table.concat(trail, " ", 1, 5))
-- Prints: global module controller route action
print(table.concat(trail, " ", 6))
-- Prints: /route /controller /module /global

-- Only the global filters see a request that matches no route.
print(get("/nothing"))
-- Prints: 404
print(table.concat(trail, " "))
-- Prints: global /global
