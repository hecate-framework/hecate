-- hecate.openapi: assembles an OpenAPI 3.1 document from route entries, project information and schemas
-- (docs/architecture/schemas-and-contracts.md, "hecate.openapi"; OpenAPI Specification 3.1.0). Step 1 of the
-- package: the document assembly. The served endpoint, the export, the lint and the contract diff come later.
global <const> require, type, pairs, ipairs, error, string, table, math, tostring, next

local core = require("hecate.core")
local json = require("hecate.json")
local schema = require("hecate.schema")
local Components = require("hecate.openapi.internal.components")
local problem_details = require("hecate.openapi.internal.problem_details")
local status = require("hecate.openapi.internal.status")

--- The contact of the API (OpenAPI 3.1 section 4.8.3).
---@class hecate.openapi.Contact
---@field name? string
---@field url? string
---@field email? string

--- The licence of the API (section 4.8.4): `identifier` (an SPDX expression) and `url` are mutually exclusive.
---@class hecate.openapi.License
---@field name string
---@field identifier? string
---@field url? string

--- Project information (section 4.8.2). The project version of the manifest is the usual `version`.
---@class hecate.openapi.Info
---@field title string
---@field version string  the version of the API, not of OpenAPI
---@field summary? string
---@field description? string
---@field terms_of_service? string  a URI
---@field contact? hecate.openapi.Contact
---@field license? hecate.openapi.License

--- A server (section 4.8.5).
---@class hecate.openapi.Server
---@field url string
---@field description? string

--- A route entry, as plain data: the shape of `hecate.kernel.RouteEntry` (this package does not depend on the
--- kernel; the fields it does not read, such as `filters` and `action`, are ignored).
---@class hecate.openapi.RouteEntry
---@field method string  upper case
---@field path string  the full path template (`{id}`, and `{rest...}` for a wildcard)
---@field name string  unique; becomes the `operationId`
---@field summary? string
---@field description? string
---@field tags? string[]
---@field deprecated? boolean
---@field parameters? { path?: table<string, hecate.schema.Schema>, query?: table<string, hecate.schema.Schema>, fields?: table<string, hecate.schema.Schema>, cookies?: table<string, hecate.schema.Schema> }
---@field content? table<string, hecate.schema.Schema>  request schema per media type
---@field responses? table<integer, hecate.schema.Schema|table|true>  schema, problem class (`status`, `title`) or `true`
---@field security? table[]  requirements, kept as declared

--- Options of `build`.
---@class hecate.openapi.BuildOptions
---@field info hecate.openapi.Info
---@field routes hecate.openapi.RouteEntry[]
---@field servers? hecate.openapi.Server[]

--- Document assembly and encoding.
---@class hecate.openapi
local openapi = {}

--- The version of the OpenAPI Specification the documents follow.
openapi.VERSION = "3.1.0"

local METHODS <const> = { GET = "get", PUT = "put", POST = "post", DELETE = "delete", OPTIONS = "options",
  HEAD = "head", PATCH = "patch" }

local function refuse(message, context)
  error(core.ArgumentError("hecate.openapi.build: " .. message, context and { context = context } or nil), 0)
end

local function describe(value)
  if type(value) == "string" then return ("string %q"):format(value) end
  return type(value)
end

--- Checks that `value` is a table whose keys are among `allowed` and returns it.
local function check_table(value, where, allowed)
  if type(value) ~= "table" then refuse(where .. " must be a table, got " .. describe(value)) end
  for key in pairs(value) do
    if not allowed[key] then refuse(("unknown field %s in %s"):format(describe(key), where)) end
  end
  return value
end

local function check_string(value, where, required)
  if value == nil and not required then return nil end
  if type(value) ~= "string" or value == "" then refuse(where .. " must be a non-empty string, got " .. describe(value)) end
  return value
end

local function copy_fields(source, target, where, names)
  for from, to in pairs(names) do
    target[to] = check_string(source[from], where .. "." .. from, false)
  end
end

local function info_object(info)
  check_table(info, "info", { title = true, version = true, summary = true, description = true, terms_of_service = true,
    contact = true, license = true })
  check_string(info.title, "info.title", true)
  check_string(info.version, "info.version", true)
  local object = { title = info.title, version = info.version }
  copy_fields(info, object, "info", { summary = "summary", description = "description", terms_of_service = "termsOfService" })
  if info.contact ~= nil then
    check_table(info.contact, "info.contact", { name = true, url = true, email = true })
    object.contact = {}
    copy_fields(info.contact, object.contact, "info.contact", { name = "name", url = "url", email = "email" })
  end
  if info.license ~= nil then
    check_table(info.license, "info.license", { name = true, identifier = true, url = true })
    check_string(info.license.name, "info.license.name", true)
    if info.license.identifier ~= nil and info.license.url ~= nil then
      refuse("info.license has both identifier and url; OpenAPI 3.1 section 4.8.4 makes them mutually exclusive")
    end
    object.license = {}
    copy_fields(info.license, object.license, "info.license", { name = "name", identifier = "identifier", url = "url" })
  end
  return object
end

local function servers_list(servers)
  if servers == nil then return nil end
  if type(servers) ~= "table" then refuse("servers must be a list, got " .. describe(servers)) end
  local list = {}
  for index, server in ipairs(servers) do
    local where = "servers[" .. index .. "]"
    check_table(server, where, { url = true, description = true })
    check_string(server.url, where .. ".url", true)
    list[index] = { url = server.url, description = check_string(server.description, where .. ".description", false) }
  end
  if #list == 0 then return nil end
  return list
end

--- A path template of the router as an OpenAPI path template (section 4.8.2): `{rest...}` is written `{rest}`.
---@param path string
---@return string
local function openapi_path(path)
  return (string.gsub(path, "{([%a_][%w_]*)%.%.%.}", "{%1}"))
end

local function sorted_keys(map)
  local keys = {}
  for key in pairs(map) do keys[#keys + 1] = key end
  table.sort(keys)
  return keys
end

--- The parameter objects of one location, ordered by name (section 4.8.12).
local LOCATIONS <const> = { { "path", "path" }, { "query", "query" }, { "fields", "header" }, { "cookies", "cookie" } }

local function parameters_of(entry, components, where)
  local list = {}
  local declared = entry.parameters or {}
  for _, location in ipairs(LOCATIONS) do
    local map = declared[location[1]] or {}
    for _, name in ipairs(sorted_keys(map)) do
      local s = map[name]
      local required = location[2] == "path" or (s.kind ~= "optional" and s.kind ~= "default")
      list[#list + 1] = { name = name, ["in"] = location[2], required = required,
        schema = components:convert(s, where .. " parameter " .. name) }
    end
  end
  if #list == 0 then return nil end
  return list
end

local function responses_of(entry, components, where)
  local responses = {}
  local any = false
  for code, declared in pairs(entry.responses or {}) do
    any = true
    local key = tostring(code)
    if declared == true then
      responses[key] = { description = status.description(code) }
    elseif problem_details.is_class(declared) then
      responses[key] = { description = declared.title, content = { [problem_details.MEDIA_TYPE] = {
        schema = { ["$ref"] = "#/components/schemas/" .. problem_details.NAME } } } }
    else
      responses[key] = { description = status.description(code), content = { ["application/json"] = {
        schema = components:convert(declared, where .. " response " .. key) } } }
    end
  end
  -- OpenAPI 3.1 section 4.8.16: `responses` holds at least one response. A route that declares none still
  -- appears, with a `default` response that says so; the lint of a later step reports it.
  if not any then responses.default = { description = "No response is declared for this route." } end
  return responses
end

local function operation_of(entry, components)
  local where = ("route %q"):format(entry.name)
  local operation = {
    operationId = entry.name, summary = entry.summary, description = entry.description,
    deprecated = entry.deprecated == true or nil,
    parameters = parameters_of(entry, components, where),
    responses = responses_of(entry, components, where),
  }
  if entry.tags ~= nil and #entry.tags > 0 then
    operation.tags = {}
    for index, tag in ipairs(entry.tags) do operation.tags[index] = tag end
  end
  if entry.content ~= nil and next(entry.content) ~= nil then
    local content = {}
    for media_type, s in pairs(entry.content) do
      content[media_type] = { schema = components:convert(s, where .. " request content " .. media_type) }
    end
    operation.requestBody = { required = true, content = content }
  end
  if entry.security ~= nil and #entry.security > 0 then
    operation.security = {}
    for index, requirement in ipairs(entry.security) do operation.security[index] = requirement end
  end
  return operation
end

local function check_entry(entry, index)
  local where = "routes[" .. index .. "]"
  if type(entry) ~= "table" then refuse(where .. " must be a route entry (a table), got " .. describe(entry)) end
  if type(entry.method) ~= "string" or METHODS[entry.method] == nil then
    refuse(where .. ".method must be an HTTP method in upper case, got " .. describe(entry.method))
  end
  if type(entry.path) ~= "string" or string.sub(entry.path, 1, 1) ~= "/" then
    refuse(where .. ".path must be a path template starting with '/', got " .. describe(entry.path))
  end
  check_string(entry.name, where .. ".name", true)
  for _, field in ipairs({ "content", "responses" }) do
    if entry[field] ~= nil and type(entry[field]) ~= "table" then refuse(where .. "." .. field .. " must be a table, got " .. describe(entry[field])) end
  end
  for _, map in pairs(entry.content or {}) do
    if not schema.is_schema(map) then refuse(where .. ".content must hold schemas (hecate.schema)") end
  end
  for code, declared in pairs(entry.responses or {}) do
    if math.type(code) ~= "integer" or code < 100 or code > 599 then
      refuse(where .. ".responses keys are status codes (100..599), got " .. describe(code))
    end
    if declared ~= true and not schema.is_schema(declared) and not problem_details.is_class(declared) then
      refuse(("%s.responses[%d] must be a schema, a problem class or true, got %s"):format(where, code, describe(declared)))
    end
  end
  for _, location in pairs(entry.parameters or {}) do
    for name, s in pairs(location) do
      if not schema.is_schema(s) then refuse(("%s.parameters %q must be a schema (hecate.schema)"):format(where, tostring(name))) end
    end
  end
end

--- Assembles an OpenAPI 3.1 document, a table of plain values that `encode` writes. Every route of `routes` appears
--- as one operation, in whatever order the routes are given: the content of the result does not depend on it,
--- which keeps contract diffs stable. The schemas of `hecate.schema` are emitted with `to_json_schema`; their
--- `$defs` become `components.schemas` and their references `#/components/schemas/...` (OQ-89). The problem details
--- schema (RFC 9457) is the component `ProblemDetails`, referenced by the responses declared with a problem class.
--- Raises `hecate.core.ArgumentError` for invalid options, for two routes with the same method and path or the same
--- name, and for two different schemas under one component name.
---@param options hecate.openapi.BuildOptions
---@return table document
function openapi.build(options)
  check_table(options, "options", { info = true, routes = true, servers = true })
  if options.info == nil then refuse("options.info is required") end
  if type(options.routes) ~= "table" then refuse("options.routes must be a list of route entries, got " .. describe(options.routes)) end
  local document = { openapi = openapi.VERSION, info = info_object(options.info), servers = servers_list(options.servers) }

  local components = Components()
  components:define(problem_details.NAME, problem_details.schema(), "the built-in problem details schema")

  local entries = {}
  local operations, names = {}, {}
  for index, entry in ipairs(options.routes) do
    check_entry(entry, index)
    local key = entry.method .. " " .. openapi_path(entry.path)
    if operations[key] then refuse(("two routes document the operation %s (%q and %q)"):format(key, operations[key], entry.name), { operation = key }) end
    if names[entry.name] then refuse(("two routes are named %q"):format(entry.name), { name = entry.name }) end
    operations[key], names[entry.name] = entry.name, entry.name
    entries[#entries + 1] = { key = key, entry = entry }
  end
  table.sort(entries, function(a, b)
    local pa, pb = openapi_path(a.entry.path), openapi_path(b.entry.path)
    if pa ~= pb then return pa < pb end
    return a.entry.method < b.entry.method
  end)

  local paths, tag_set = {}, {}
  for _, item in ipairs(entries) do
    local entry = item.entry
    local path = openapi_path(entry.path)
    paths[path] = paths[path] or {}
    paths[path][METHODS[entry.method]] = operation_of(entry, components)
    for _, tag in ipairs(entry.tags or {}) do tag_set[tag] = true end
  end
  document.paths = paths
  local tags = {}
  for _, name in ipairs(sorted_keys(tag_set)) do tags[#tags + 1] = { name = name } end
  if #tags > 0 then document.tags = tags end
  document.components = { schemas = components.schemas }
  return document
end

--- Encodes a document as JSON text with the members of every object in a fixed order (`canonical`, RFC 8785
--- section 3.2.3), so that two equal documents give the same bytes.
---@param document table
---@param options? { pretty?: boolean, indent?: integer|string }
---@return string
function openapi.encode(document, options)
  local encode_options = { canonical = true }
  if options ~= nil then
    encode_options.pretty = options.pretty
    encode_options.indent = options.indent
  end
  return json.encode(document, encode_options)
end

return openapi
