-- The route entry: the single normalised shape that both declaration styles (controllers and route modules) produce
-- and that `hecate.router` compiles (ADR 0006, http-and-routing.md "Route declaration"). Everything is validated here,
-- when a route is declared, never lazily at the first request.
global <const> require, type, error, pairs, ipairs, tostring, table, string, math

local schema = require("hecate.schema")
local template = require("hecate.router").template
local chain = require("hecate.kernel.chain")
local problem = require("hecate.kernel.problem")
local errors = require("hecate.kernel.errors")

--- One normalised route entry. Every field except `summary`, `description` and `controller` is always present, so two
--- equivalent declarations give two equal entries (apart from the action, which is a method name for a controller and
--- a function for a route module, and from `origin` and `controller`). It is also a `hecate.router.Route`.
---@class hecate.kernel.RouteEntry
---@field method string  an HTTP method, upper case (RFC 9110 section 9.1)
---@field path string  the full path template: the prefix of a controller, then the declared path
---@field name string  unique in the route table; `<method> <path>` unless declared
---@field summary? string
---@field description? string
---@field tags string[]
---@field deprecated boolean
---@field parameters hecate.kernel.RouteParameters
---@field content table<string, hecate.schema.Schema>  request schema per media type
---@field responses table<integer, hecate.schema.Schema|table>  schema (or problem class) per status code
---@field security table[]  requirements, kept as declared (the `security` package defines their shape)
---@field filters hecate.kernel.Filter[]  outermost first: those of the controller, then those of the route
---@field action string|fun(request: any): any  a method name of `controller`, or an action function
---@field controller? table  the controller class, for a controller route
---@field origin string  the route module or the controller that declared it, for diagnostics

--- The parameters of a route, by location. `fields` are the header fields (OpenAPI `in: header`).
---@class hecate.kernel.RouteParameters
---@field path table<string, hecate.schema.Schema>
---@field query table<string, hecate.schema.Schema>
---@field fields table<string, hecate.schema.Schema>
---@field cookies table<string, hecate.schema.Schema>

--- What a route declaration contains (http-and-routing.md "Route declaration"). `method` and `path` are given by the
--- verb of a route module (`routes:get "/x" { ... }`) and by `method`/`path` in a controller.
---@class hecate.kernel.RouteSpec
---@field method? string  controllers only
---@field path? string  controllers only (relative to the prefix)
---@field name? string
---@field summary? string
---@field description? string
---@field tags? string[]
---@field deprecated? boolean
---@field parameters? { path?: table<string, hecate.schema.Schema>, query?: table<string, hecate.schema.Schema>, fields?: table<string, hecate.schema.Schema>, cookies?: table<string, hecate.schema.Schema> }
---@field content? table<string, hecate.schema.Schema>
---@field responses? table<integer, hecate.schema.Schema|table>
---@field security? table[]
---@field filters? hecate.kernel.Filter[]
---@field action string|fun(request: any): any  a method name (controller) or a function (route module)

--- Normalisation and checks of route entries.
---@class hecate.kernel.route
local route = {}

local RouteDeclarationError = errors.RouteDeclarationError

--- The methods a route may declare: the standard ones the router serves (RFC 9110 section 9.3), case-sensitive.
route.METHODS = { "GET", "HEAD", "POST", "PUT", "PATCH", "DELETE", "OPTIONS" }
local METHOD_SET <const> = {}
for _, method in ipairs(route.METHODS) do METHOD_SET[method] = true end

local KNOWN <const> = {
  method = true, path = true, name = true, summary = true, description = true, tags = true, deprecated = true,
  parameters = true, content = true, responses = true, security = true, filters = true, action = true,
}
local LOCATIONS <const> = { "path", "query", "fields", "cookies" }

local function refuse(origin, reason, field, message)
  error(RouteDeclarationError(("kernel: %s: %s"):format(origin, message), {
    context = { reason = reason, origin = origin, field = field },
  }))
end

--- Raises a `RouteDeclarationError` (shared with route modules, for the checks of their options).
---@type fun(origin: string, reason: string, field: string?, message: string)
route.refuse = refuse

local function is_list(value)
  if type(value) ~= "table" then return false end
  local count = 0
  for key in pairs(value) do
    if math.type(key) ~= "integer" or key < 1 then return false end
    count = count + 1
  end
  return count == #value
end

--- Copies a map of schemas, checking the keys (strings) and the values (schemas).
local function schema_map(origin, reason, field, value, what)
  if type(value) ~= "table" then refuse(origin, reason, field, field .. " must be a table of " .. what) end
  local copy = {}
  for key, item in pairs(value) do
    if type(key) ~= "string" or key == "" then refuse(origin, reason, field, field .. " keys must be non-empty strings") end
    if not schema.is_schema(item) then
      refuse(origin, reason, field, ("%s[%q] must be a schema (hecate.schema)"):format(field, key))
    end
    copy[key] = item
  end
  return copy
end

local function sorted_keys(map)
  local keys = {}
  for key in pairs(map) do keys[#keys + 1] = key end
  table.sort(keys)
  return keys
end

--- Joins a controller prefix and a declared path. The prefix is empty or starts with `/` and does not end with one;
--- the path `/` stands for the prefix itself (`/users` and `/`: `/users`).
local function join(origin, prefix, path)
  if prefix == nil or prefix == "" then return path end
  if type(prefix) ~= "string" or string.byte(prefix, 1) ~= 47 or string.byte(prefix, -1) == 47 then
    refuse(origin, "invalid_path", "prefix", "prefix must be empty or start with '/' and not end with '/': " .. tostring(prefix))
  end
  if path == "/" then return prefix end
  return prefix .. path
end

--- Options of `route.normalise`.
---@class hecate.kernel.NormaliseOptions
---@field origin string  the route module or controller, for diagnostics
---@field method? string  fixed by the verb of a route module
---@field prefix? string  the prefix of a controller
---@field filters? hecate.kernel.Filter[]  filters of the enclosing controller, outermost first
---@field controller? table  the controller class (the action is then a method name)

--- Validates a route declaration and returns its normalised entry. Raises `RouteDeclarationError` (never a Lua error
--- message) for an unknown field, a bad method, an invalid or mismatched path template, a bad schema, a bad
--- filter or a bad action. Whether a controller has the method named by the action is checked later, by
--- `route.check_action`, because a controller declares its routes before its methods.
---@param spec hecate.kernel.RouteSpec
---@param options hecate.kernel.NormaliseOptions
---@return hecate.kernel.RouteEntry
function route.normalise(spec, options)
  local origin = options.origin
  if type(spec) ~= "table" then refuse(origin, "invalid_source", nil, "a route declaration is a table") end
  for key in pairs(spec) do
    if type(key) ~= "string" or not KNOWN[key] then
      refuse(origin, "unknown_field", tostring(key), "unknown field " .. tostring(key))
    end
  end
  local method = options.method or spec.method
  if type(method) ~= "string" or not METHOD_SET[method] then
    refuse(origin, "invalid_method", "method", "method must be one of " .. table.concat(route.METHODS, ", ")
      .. " (upper case, RFC 9110 section 9.1), got " .. tostring(method))
  end
  if type(spec.path) ~= "string" or string.byte(spec.path, 1) ~= 47 then
    refuse(origin, "invalid_path", "path", "path must be a string starting with '/', got " .. tostring(spec.path))
  end
  local path = join(origin, options.prefix, spec.path)
  local parsed, reason, detail = template.parse(path, "ignore")
  if parsed == nil then
    refuse(origin, "invalid_path", "path", ("invalid path template %s (%s): %s"):format(path, tostring(reason), tostring(detail)))
  end
  ---@cast parsed hecate.router.Template
  local name = spec.name
  if name == nil then
    name = method .. " " .. path
  elseif type(name) ~= "string" or name == "" then
    refuse(origin, "invalid_name", "name", "name must be a non-empty string")
  end
  for _, field in ipairs({ "summary", "description" }) do
    local value = spec[field]
    if value ~= nil and type(value) ~= "string" then refuse(origin, "invalid_text", field, field .. " must be a string") end
  end
  local tags = {}
  if spec.tags ~= nil then
    if not is_list(spec.tags) then refuse(origin, "invalid_tags", "tags", "tags must be a list of strings") end
    for index, tag in ipairs(spec.tags) do
      if type(tag) ~= "string" or tag == "" then
        refuse(origin, "invalid_tags", "tags", "tags[" .. index .. "] must be a non-empty string")
      end
      tags[index] = tag
    end
  end
  if spec.deprecated ~= nil and type(spec.deprecated) ~= "boolean" then
    refuse(origin, "invalid_deprecated", "deprecated", "deprecated must be a boolean")
  end

  local parameters = {}
  local declared = spec.parameters
  if declared ~= nil then
    if type(declared) ~= "table" then refuse(origin, "invalid_parameters", "parameters", "parameters must be a table") end
    for key in pairs(declared) do
      if key ~= "path" and key ~= "query" and key ~= "fields" and key ~= "cookies" then
        refuse(origin, "invalid_parameters", "parameters", "unknown parameter location " .. tostring(key)
          .. " (path, query, fields, cookies)")
      end
    end
  end
  for _, location in ipairs(LOCATIONS) do
    local at = declared and declared[location]
    parameters[location] = at == nil and {}
      or schema_map(origin, "invalid_parameters", "parameters." .. location, at, "schemas by parameter name")
  end
  -- http-and-routing.md: the parameters of the template match the declared `parameters.path`, both ways.
  local in_template = {}
  for _, parameter in ipairs(parsed.names) do in_template[parameter] = true end
  for _, parameter in ipairs(parsed.names) do
    if parameters.path[parameter] == nil then
      refuse(origin, "parameter_mismatch", "parameters.path",
        ("path %s has the parameter {%s} that parameters.path does not declare"):format(path, parameter))
    end
  end
  for _, parameter in ipairs(sorted_keys(parameters.path)) do
    if not in_template[parameter] then
      refuse(origin, "parameter_mismatch", "parameters.path",
        ("parameters.path declares %q, which path %s does not contain"):format(parameter, path))
    end
  end

  local content = {}
  if spec.content ~= nil then
    content = schema_map(origin, "invalid_content", "content", spec.content, "schemas by media type")
    for media_type in pairs(content) do
      if not string.find(media_type, "^[^/%s]+/[^/%s]+$") then
        refuse(origin, "invalid_content", "content", ("content key %q is not a media type (RFC 9110 section 8.3.1)"):format(media_type))
      end
    end
  end

  local responses = {}
  if spec.responses ~= nil then
    if type(spec.responses) ~= "table" then refuse(origin, "invalid_responses", "responses", "responses must be a table by status code") end
    for status, representation in pairs(spec.responses) do
      if math.type(status) ~= "integer" or status < 100 or status > 599 then
        refuse(origin, "invalid_responses", "responses", "responses keys are status codes (100..599), got " .. tostring(status))
      end
      if not schema.is_schema(representation) and not problem.is_class(representation) then
        refuse(origin, "invalid_responses", "responses",
          ("responses[%d] must be a schema or a problem class (hecate.kernel.problem)"):format(status))
      end
      responses[status] = representation
    end
  end

  local security = {}
  if spec.security ~= nil then
    if not is_list(spec.security) then refuse(origin, "invalid_security", "security", "security must be a list of requirements") end
    for index, requirement in ipairs(spec.security) do security[index] = requirement end
  end

  local filters = {}
  if options.filters ~= nil then
    if not is_list(options.filters) then refuse(origin, "invalid_filters", "filters", "filters of the controller must be a list of filters") end
    for index, filter in ipairs(options.filters) do
      if not chain.is_filter(filter) then
        refuse(origin, "invalid_filters", "filters", "filters[" .. index .. "] of the controller is not a filter")
      end
      filters[#filters + 1] = filter
    end
  end
  if spec.filters ~= nil then
    if not is_list(spec.filters) then refuse(origin, "invalid_filters", "filters", "filters must be a list of filters") end
    for index, filter in ipairs(spec.filters) do
      if not chain.is_filter(filter) then
        refuse(origin, "invalid_filters", "filters", "filters[" .. index .. "] is not a filter (a table with a handle function)")
      end
      filters[#filters + 1] = filter
    end
  end

  local action = spec.action
  if options.controller ~= nil then
    if type(action) ~= "string" or action == "" then
      refuse(origin, "invalid_action", "action", "the action of a controller route is the name of a method")
    end
  elseif type(action) ~= "function" then
    refuse(origin, "invalid_action", "action", "the action of a route module route is a function")
  end

  return {
    method = method,
    path = path,
    name = name,
    summary = spec.summary,
    description = spec.description,
    tags = tags,
    deprecated = spec.deprecated or false,
    parameters = parameters,
    content = content,
    responses = responses,
    security = security,
    filters = filters,
    action = action,
    controller = options.controller,
    origin = origin,
  }
end

--- Checks a prefix (the rule of a controller prefix, shared by the options of a route module). Raises
--- `RouteDeclarationError` with reason `invalid_path` and field `prefix`.
---@param origin string
---@param prefix any
function route.check_prefix(origin, prefix)
  join(origin, prefix, "/")
end

--- Checks a list of filters and returns a copy of it. Raises `RouteDeclarationError` with reason `invalid_filters`.
---@param origin string
---@param filters any
---@param what string  how the list is named in the message, e.g. "the default filters"
---@return hecate.kernel.Filter[]
function route.check_filters(origin, filters, what)
  if not is_list(filters) then refuse(origin, "invalid_filters", "filters", what .. " must be a list of filters") end
  local copy = {}
  for index, filter in ipairs(filters) do
    if not chain.is_filter(filter) then
      refuse(origin, "invalid_filters", "filters", what .. "[" .. index .. "] is not a filter (a table with a handle function)")
    end
    copy[index] = filter
  end
  return copy
end

--- Checks that the action of a controller route names a method of the (finalised) class. Raises
--- `RouteDeclarationError` with reason `missing_action` otherwise.
---@param entry hecate.kernel.RouteEntry
function route.check_action(entry)
  local controller = entry.controller
  if controller ~= nil and type(controller[entry.action]) ~= "function" then
    refuse(entry.origin, "missing_action", "action",
      ("route %q: the action %q is not a method of the controller"):format(entry.name, tostring(entry.action)))
  end
end

return route
