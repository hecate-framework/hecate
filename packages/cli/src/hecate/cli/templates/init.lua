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
local CONFIG_MODULE = "hecate" .. ".config"

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
  -- `hecate doc build`: the conventional layout (guides in docs/, sources in src/, the sites in docs/dist/).
  doc = {
    guides_dir = "docs",
    output_dir = "docs/dist",
    sources_dir = "src",
    package_name = %q,
  },
}
]], parameters.name, parameters.hecate_constraint, parameters.name)

  files["main.lua"] = string.format([[
-- Starts the application: `hecate serve`, or `lua main.lua` from this directory (port from PORT, default 8080).
package.path = "src/?.lua;src/?/init.lua;" .. package.path

local reactor = require("hecate.reactor")
local config = require(%q)
local %s = require(%q)

-- The configuration: `config/<environment>.lua` and the `HECATE_*` variables (`hecate serve --workers N` sets
-- `HECATE_SERVER__WORKERS`). Declare the keys of the application in `properties`.
local configuration = config.load({ properties = {} })
local port = tonumber(os.getenv("PORT") or "") or 8080
local app = %s.application({ configuration = configuration, server = { host = "127.0.0.1", port = port } })
reactor.run(function() app:serve() end)
]], CONFIG_MODULE, module, module, module)

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

  -- The documentation: what `hecate doc build` needs to build a site (the site configuration and a first page).
  files["docs/site.lua"] = string.format([[
-- Site configuration of the documentation, read by `hecate doc build` (data only).
return {
  title = %q,
  description = "The documentation of %s.",
  base_path = "/",
}
]], parameters.name, parameters.name)
  files["docs/maintainer/en/index.md"] = string.format([[
---
description: What %s is and how to work on it.
order: 0
---

# %s

Write the documentation of the project here: one Markdown file per page in `docs/maintainer/en/`. Build the site with
`hecate doc build`; the pages, the search and the navigation come with it.
]], parameters.name, parameters.name)

  files[".gitignore"] = "lua_modules/\n.hecate/\ndocs/dist/\ndocs/maintainer/*/configuration.md\ndocs/maintainer/*/third-party-licences.md\n"
  files["README.md"] = string.format("# %s\n\nA Hecate application.\n\n```sh\nhecate install\nhecate serve --env development   # on a developer machine; production is the default\nhecate test\n```\n", parameters.name)
  return files
end

--- The `api` template: the `minimal` project plus a resource (`items`) with its schemas, its route module and tests.
---@param parameters hecate.cli.TemplateParameters
---@return table<string, string>
local function api(parameters)
  local files = minimal(parameters)
  local module = parameters.module
  files["src/" .. module .. "/schemas.lua"] = [[
-- The schemas of the API: the contract of its requests and responses.
local schema = require("hecate.schema")

local schemas = {}

schemas.NewItem = schema.object({
  name = schema.string({ min_length = 1, max_length = 80 }),
})

schemas.ItemId = schema.integer()

schemas.Item = schema.object({
  id = schemas.ItemId,
  name = schema.string(),
})

schemas.Items = schema.array(schemas.Item)

return schemas
]]

  files["src/" .. module .. "/items.lua"] = string.format([[
-- The route module of the items: create, list and show, over a store that lives in memory.
-- Replace the store with a database when the project needs one.
local hecate = require("hecate")
local schemas = require(%q)

local items = {}

--- A new, empty store.
---@return { next_id: integer, by_id: table<integer, table> }
function items.store()
  return { next_id = 0, by_id = {} }
end

--- The route module of the items over `store`.
---@param store { next_id: integer, by_id: table<integer, table> }
---@return hecate.kernel.RouteModule
function items.routes(store)
  local routes = hecate.routes("items")

  routes:get("/items", {
    name = "items.list",
    summary = "Lists the items",
    responses = { [200] = schemas.Items },
    action = function()
      local list = {}
      for id = 1, store.next_id do list[#list + 1] = store.by_id[id] end
      return list
    end,
  })

  routes:get("/items/{id}", {
    name = "items.show",
    summary = "Shows an item",
    parameters = { path = { id = schemas.ItemId } },
    responses = { [200] = schemas.Item, [404] = hecate.problem.NotFound, [422] = hecate.problem.UnprocessableContent },
    action = function(request)
      local item = store.by_id[assert(request.parameters.path).id]
      if not item then return hecate.problem.NotFound({ detail = "no such item" }) end
      return item
    end,
  })

  routes:post("/items", {
    name = "items.create",
    summary = "Creates an item",
    content = { ["application/json"] = schemas.NewItem },
    responses = { [201] = schemas.Item, [422] = hecate.problem.UnprocessableContent },
    action = function(request)
      store.next_id = store.next_id + 1
      local item = { id = store.next_id, name = assert(request.content).name }
      store.by_id[item.id] = item
      return hecate.respond(201, item)
    end,
  })

  return routes
end

return items
]], module .. ".schemas")

  files["src/" .. module .. "/init.lua"] = string.format([[
-- The application of %s: a health check and the items.
local schema = require("hecate.schema")
local hecate = require("hecate")
local items = require(%q)

local app = {}

--- The route module of the health check.
---@return hecate.kernel.RouteModule
function app.health_routes()
  local health = hecate.routes("health")
  health:get("/health", {
    name = "health.check",
    summary = "Liveness probe",
    responses = { [200] = schema.object({ status = schema.string() }) },
    action = function() return { status = "ok" } end,
  })
  return health
end

--- The route modules of the application over a store.
---@param store? { next_id: integer, by_id: table<integer, table> }  default: a new, empty store
---@return hecate.kernel.RouteModule[]
function app.routes(store)
  return { app.health_routes(), items.routes(store or items.store()) }
end

--- Builds the application. `options` are those of `hecate.Application`.
---@param options? hecate.kernel.ApplicationOptions
---@return hecate.kernel.Application
function app.application(options)
  local merged = { routes = app.routes() }
  for key, value in pairs(options or {}) do merged[key] = value end
  return hecate.Application(merged)
end

return app
]], parameters.name, module .. ".items")

  files["tests/" .. module .. "_test.lua"] = string.format([[
local test = require(%q)
local %s = require(%q)

local T = test.Case("%sTest")

function T:test_the_health_check_answers_ok()
  local client = test.boot({ routes = %s.routes() })
  local response = client:get("/health")
  self:assert_equal(200, response.status)
  self:assert_equal("ok", response:read_json().status)
end

function T:test_an_item_is_created_then_shown_and_listed()
  local client = test.boot({ routes = %s.routes() })
  local created = client:post("/items", { json = { name = "first" } })
  self:assert_equal(201, created.status)
  self:assert_equal(1, created:read_json().id)
  self:assert_equal("first", client:get("/items/1"):read_json().name)
  self:assert_equal(1, #client:get("/items"):read_json())
end

function T:test_an_unknown_item_is_a_404_problem()
  local client = test.boot({ routes = %s.routes() })
  self:assert_equal(404, client:get("/items/99").status)
end

function T:test_an_item_without_a_name_is_a_422_problem()
  local client = test.boot({ routes = %s.routes() })
  self:assert_equal(422, client:post("/items", { json = { name = "" } }).status)
end

return T
]], TEST_MODULE, module, module, module, module, module, module, module)

  -- The contract section: what `hecate contract export` needs (title and version of the OpenAPI document).
  local section = string.format("\n  contract = { title = %q, version = \"0.1.0\" },\n}\n", parameters.name)
  files["hecate.project.lua"] = (files["hecate.project.lua"]:gsub("\n}\n$", function() return section end))
  files["README.md"] = string.format("# %s\n\nA Hecate API: a health check and a resource (`items`) with its contract.\n\n```sh\nhecate install\nhecate serve --env development   # on a developer machine; production is the default\nhecate test\nhecate contract export --output=openapi.json\n```\n", parameters.name)
  return files
end

--- The templates by name.
---@type table<string, hecate.cli.Template>
M.templates = { minimal = minimal, api = api }

--- The names of the templates, sorted.
---@return string[] names
function M.names()
  local names = {}
  for name in pairs(M.templates) do names[#names + 1] = name end
  table.sort(names)
  return names
end

return M
