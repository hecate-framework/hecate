-- The project templates of `hecate new` (cli-and-packaging.md, "Templates"). A template is a function of the project
-- name, the module name and the Hecate version line that returns the files to write, by relative path.
global <const> require, table, string, pairs, ipairs, error, type

local core = require("hecate.core")

---@class hecate.cli.TemplateParameters
---@field name string  the project name, as written in the manifest
---@field module string  the Lua module of the project (the name with '-' and '.' turned into '_')
---@field hecate_constraint string  LuaRocks constraint on the `hecate` rock, for example "~> 0.1"

---@alias hecate.cli.Template fun(parameters: hecate.cli.TemplateParameters): table<string, string>

---@class hecate.cli.templates
local M = {}

--- The module the generated tests require. It is project text, not a dependency of the CLI, so it is built here
--- instead of appearing as a `require` (`check-boundaries` reads the sources).
local TEST_MODULE = "hecate" .. ".test"

--- The module name of a project: the name with every character that is not a letter, digit or '_' turned into '_'.
--- Raises `hecate.core.ArgumentError` for a name that would not make an identifier.
---@param name string
---@return string module
function M.module_name(name)
  local module = name:gsub("[^%w_]", "_")
  if not module:match("^[%a_]") then
    error(core.ArgumentError("'" .. name .. "' cannot name a Lua module (it must start with a letter): choose a name such as 'my-api'"), 0)
  end
  return module
end

---@param parameters hecate.cli.TemplateParameters
---@return table<string, string>
local function minimal(parameters)
  local files = {}
  local module = parameters.module
  files["hecate.project.lua"] = string.format([[
return {
  name = %q,
  version = "0.1.0",
  lua = "5.5",
  dependencies = {
    hecate = %q,
  },
}
]], parameters.name, parameters.hecate_constraint)

  files["main.lua"] = string.format([[
-- Starts the application: `hecate serve`, or `lua main.lua` from this directory (port from PORT, default 8080).
package.path = "src/?.lua;src/?/init.lua;" .. package.path

local reactor = require("hecate.reactor")
local %s = require(%q)

local port = tonumber(os.getenv("PORT") or "") or 8080
local app = %s.application({ server = { host = "127.0.0.1", port = port } })
reactor.run(function() app:serve() end)
]], module, module, module)

  files["src/" .. module .. "/init.lua"] = string.format([[
-- The application of %s: one route module.
local schema = require("hecate.schema")
local hecate = require("hecate")

local app = {}

--- The route module of the health check.
---@return hecate.kernel.RouteModule
function app.routes()
  local health = hecate.routes("health")
  health:get("/health", {
    name = "health.check",
    summary = "Liveness probe",
    responses = { [200] = schema.object({ status = schema.string() }) },
    action = function() return { status = "ok" } end,
  })
  return health
end

--- Builds the application. `options` are those of `hecate.Application`.
---@param options? hecate.kernel.ApplicationOptions
---@return hecate.kernel.Application
function app.application(options)
  local merged = { routes = { app.routes() } }
  for key, value in pairs(options or {}) do merged[key] = value end
  return hecate.Application(merged)
end

return app
]], parameters.name)

  files["tests/" .. module .. "_test.lua"] = string.format([[
local test = require(%q)
local %s = require(%q)

local T = test.Case("%sTest")

function T:test_the_health_check_answers_ok()
  local client = test.boot({ routes = { %s.routes() } })
  local response = client:get("/health")
  self:assert_equal(200, response.status)
  self:assert_equal("ok", response:read_json().status)
end

return T
]], TEST_MODULE, module, module, module, module)

  files[".gitignore"] = "lua_modules/\n.hecate/\n"
  files["README.md"] = string.format("# %s\n\nA Hecate application.\n\n```sh\nhecate install\nhecate serve\nhecate test\n```\n", parameters.name)
  return files
end

--- The templates by name.
---@type table<string, hecate.cli.Template>
M.templates = { minimal = minimal }

--- The names of the templates, sorted.
---@return string[] names
function M.names()
  local names = {}
  for name in pairs(M.templates) do names[#names + 1] = name end
  table.sort(names)
  return names
end

return M
