-- Contract providers: documents rendered from the route table (such as the OpenAPI document) and served by a GET route.
-- The kernel does not know the document formats: a provider is plain data and a function (see `hecate.openapi.provider`).
global <const> require, type, error, ipairs, pairs, tostring

local core = require("hecate.core")
local http = require("hecate.http")
local RouteModule = require("hecate.kernel.routes")

--- What a contract provider is: plain data, so that a package of a lower layer can make one.
---@class hecate.kernel.ContractProvider
---@field name string  the route name (mandatory, unique among the routes)
---@field path string  the path served, starting with `/`
---@field media_type string  the `Content-Type` of the document
---@field render fun(entries: hecate.kernel.RouteEntry[]): string  renders the document; called at most once, at the first request
---@field enabled? boolean  `false` serves nothing (default true)
---@field summary? string

--- The contract machinery of the application.
---@class hecate.kernel.contract
local contract = {}

local FIELDS <const> = { name = true, path = true, media_type = true, render = true, enabled = true, summary = true }

local function refuse(message)
  error(core.ArgumentError("hecate.kernel.contract.entries: " .. message), 3)
end

--- The route entries that serve `providers`. Each document is rendered at the first request, from `documented` (the
--- route entries of the application), then kept. A failing `render` is an internal failure (generic 500, logged).
--- Raises `hecate.core.ArgumentError` for a provider that is not a table with a `name`, a `path`, a `media_type` and a `render`.
---@param providers? hecate.kernel.ContractProvider[]
---@param documented hecate.kernel.RouteEntry[]
---@return hecate.kernel.RouteEntry[]
function contract.entries(providers, documented)
  if providers == nil then return {} end
  if type(providers) ~= "table" then refuse("contracts must be a list of providers, got " .. type(providers)) end
  local module = RouteModule("contracts")
  for index, provider in ipairs(providers) do
    if type(provider) ~= "table" then refuse(("contracts[%d] must be a table, got %s"):format(index, type(provider))) end
    for key in pairs(provider) do
      if type(key) ~= "string" or not FIELDS[key] then refuse(("contracts[%d] has the unknown field %s"):format(index, tostring(key))) end
    end
    for _, key in ipairs { "name", "path", "media_type" } do
      if type(provider[key]) ~= "string" or provider[key] == "" then refuse(("contracts[%d].%s must be a non-empty string"):format(index, key)) end
    end
    if type(provider.render) ~= "function" then refuse(("contracts[%d].render must be a function"):format(index)) end
    if provider.enabled ~= false then
      local body
      local fields = http.Fields()
      fields:set("Content-Type", provider.media_type)
      module:get(provider.path, {
        name = provider.name, summary = provider.summary, responses = { [200] = true },
        action = function()
          if body == nil then body = provider.render(documented) end
          return http.Response(200, { fields = fields, content = body })
        end,
      })
    end
  end
  return module:routes()
end

return contract
