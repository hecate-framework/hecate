-- The served OpenAPI document: a GET route that renders `hecate.openapi` from the route table of the application.
global <const> require, type, error, ipairs, pairs, tostring

local core = require("hecate.core")
local http = require("hecate.http")
local openapi = require("hecate.openapi")
local RouteModule = require("hecate.kernel.routes")

--- The `openapi` option of `hecate.kernel.Application`.
---@class hecate.kernel.OpenApiOptions
---@field info hecate.openapi.Info  required
---@field servers? table
---@field tags? table
---@field external_docs? hecate.openapi.ExternalDocs
---@field path? string  default `/openapi.json`
---@field name? string  route name, default `openapi`
---@field enabled? boolean  default: true in the `development` environment of the configuration, false otherwise
---@field pretty? boolean  indented output (default false)

--- The route of the served document.
---@class hecate.kernel.contract
local contract = {}

local FIELDS <const> = { info = true, servers = true, tags = true, external_docs = true, path = true, name = true, enabled = true, pretty = true }

local function refuse(message)
  error(core.ArgumentError("hecate.kernel.contract.entries: " .. message), 3)
end

--- The route entries that serve the document (none when it is not served). The document is built from `documented`, the
--- route entries of the application, at the first request, then kept; a document that cannot be built is an internal
--- failure of that request (generic 500, logged). Raises `hecate.core.ArgumentError` for options that are not a table,
--- an unknown field, a missing `info` or a bad `path`, `name` or `enabled`.
---@param options? hecate.kernel.OpenApiOptions
---@param documented hecate.kernel.RouteEntry[]
---@param served_in_development boolean  whether the configuration says `development` (the default of `enabled`)
---@return hecate.kernel.RouteEntry[]
function contract.entries(options, documented, served_in_development)
  if options == nil then return {} end
  if type(options) ~= "table" then refuse("the openapi option must be a table, got " .. type(options)) end
  for key in pairs(options) do
    if type(key) ~= "string" or not FIELDS[key] then refuse("the openapi option has the unknown field " .. tostring(key)) end
  end
  if options.info == nil then refuse("openapi.info is required") end
  for _, key in ipairs { "path", "name" } do
    if options[key] ~= nil and (type(options[key]) ~= "string" or options[key] == "") then refuse(("openapi.%s must be a non-empty string"):format(key)) end
  end
  if options.enabled ~= nil and type(options.enabled) ~= "boolean" then refuse("openapi.enabled must be a boolean") end
  local enabled = options.enabled
  if enabled == nil then enabled = served_in_development end
  if not enabled then return {} end
  local body
  local fields = http.Fields()
  fields:set("Content-Type", "application/json")
  local module = RouteModule("openapi")
  module:get(options.path or "/openapi.json", {
    name = options.name or "openapi", summary = "OpenAPI document of this application", responses = { [200] = true },
    action = function()
      if body == nil then
        body = openapi.encode(openapi.build({ info = options.info, servers = options.servers, tags = options.tags,
          external_docs = options.external_docs, routes = documented }), { pretty = options.pretty })
      end
      return http.Response(200, { fields = fields, content = body })
    end,
  })
  return module:routes()
end

return contract
