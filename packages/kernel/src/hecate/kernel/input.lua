-- Validation and coercion of the inputs of a request by the schemas of its route (http-and-routing.md "Route
-- declaration", schemas-and-contracts.md "Coercion"). Every schema is resolved once, when the dispatcher is composed;
-- a request then pays one `build` per declared input and nothing at all for a route that declares none.
global <const> require, error, pcall, ipairs, pairs, next, table

local core = require("hecate.core")
local json = require("hecate.json")
local schema = require("hecate.schema")
local form = require("hecate.http.form")
local problems = require("hecate.kernel.problems")
local errors = require("hecate.kernel.errors")

--- Validation and coercion of the inputs of a request.
---@class hecate.kernel.input
local input = {}

local JSON <const> = "application/json"
local LOCATIONS <const> = { "path", "query", "fields", "cookies" }

--- The raw texts of one location, for the declared names only (an undeclared query parameter, header field or cookie is
--- never exposed). A name sent once is its text, a repeated one a list of texts (schema `array` reads both).
local READERS <const> = {
  ---@param request hecate.http.Request
  ---@param names string[]
  query = function(request, names)
    local raw = {}
    if request.query == nil or request.query == "" then return raw end
    -- The query component is `application/x-www-form-urlencoded` text (WHATWG URL Standard, section 5.1).
    local parsed = form.parse_urlencoded(request.query)
    for _, name in ipairs(names) do
      local all = parsed:get_all(name)
      if all[2] ~= nil then raw[name] = all elseif all[1] ~= nil then raw[name] = all[1] end
    end
    return raw
  end,
  ---@param request hecate.http.Request
  ---@param names string[]
  fields = function(request, names)
    local raw, fields = {}, request.fields
    for _, name in ipairs(names) do
      local all = fields:get_all(name)
      if all[2] ~= nil then raw[name] = all elseif all[1] ~= nil then raw[name] = all[1] end
    end
    return raw
  end,
  ---@param request hecate.http.Request
  ---@param names string[]
  cookies = function(request, names)
    local raw, sent = {}, request:cookies()
    for _, name in ipairs(names) do raw[name] = sent[name] end
    return raw
  end,
}

--- A `ValidationError` carrying `violations`, as `Schema:check` raises it.
local function failure(violations)
  return core.ValidationError(("%d violation(s)"):format(#violations), { context = { violations = violations } })
end

--- Compiles the parameters of an entry: the schema of the whole (`path`, `query`, `fields`, `cookies`, each declared
--- location an `object`, so a violation points at `/query/limit`) and, per location, the names to read. Nil when the
--- route declares no parameter.
---@param entry hecate.kernel.RouteEntry
---@return hecate.schema.Schema? root
---@return table<string, string[]>? names
local function compile_parameters(entry)
  local properties, names, declared = {}, {}, false
  for _, location in ipairs(LOCATIONS) do
    local map = entry.parameters[location]
    if next(map) ~= nil then
      declared = true
      properties[location] = schema.object(map)
      local list = {}
      for name in pairs(map) do list[#list + 1] = name end
      table.sort(list)
      names[location] = list
    end
  end
  if not declared then return nil, nil end
  return schema.object(properties), names
end

--- Compiles the content schema of an entry (the one declared for `application/json`). A route that declares only
--- other media types is refused at composition: the kernel reads JSON only until a representation is added (OQ).
---@param entry hecate.kernel.RouteEntry
---@return hecate.schema.Schema?
local function compile_content(entry)
  if next(entry.content) == nil then return nil end
  local declared = entry.content[JSON]
  if declared == nil then
    error(errors.RouteDeclarationError(
      ("kernel: %s: route %q declares content but not for %s, the only media type the kernel reads"):format(
        entry.origin, entry.name, JSON),
      { context = { reason = "unsupported_content_type", origin = entry.origin, field = "content" } }))
  end
  return declared
end

local DECODE_STATUS <const> = { size_limit = 413 }

--- Builds the step of an entry that reads, coerces and validates its inputs, or nil when it declares none (such a route
--- pays nothing). The step takes the request and returns nil when the inputs conform (it has then set
--- `request.parameters.<location>` and `request.content`) or the problem details response to answer with: `422` for
--- violations (`problems.from_error` with `input = true`), `400` for malformed content, `415` for a `Content-Type` other
--- than `application/json`, `413` for content over the limit (a `ContentError` of the reader is raised, the guard maps it).
--- It suspends while it reads the content.
---
--- Raises `RouteDeclarationError` (`unsupported_content_type`) for content declared only for another media type.
---@param entry hecate.kernel.RouteEntry
---@param options? hecate.kernel.problems.Options  `expose_details`
---@return (fun(request: hecate.http.Request): hecate.http.Response?)?
function input.compile(entry, options)
  local root, names = compile_parameters(entry)
  local content = compile_content(entry)
  if root == nil and content == nil then return nil end
  local problem_options = { input = true, expose_details = options ~= nil and options.expose_details or nil }
  -- Defaults apply to a text input whatever the method; the content schema alone follows the method (PATCH, OQ-50).
  local content_options = entry.method == "PATCH" and { method = "PATCH" } or nil
  local build_options = { coerce = true }

  local function read_parameters(request)
    ---@cast root hecate.schema.Schema
    ---@cast names table<string, string[]>
    local raw, supplied = {}, request.parameters
    for _, location in ipairs(LOCATIONS) do
      local list = names[location] --[[@as string[]?]]
      if list ~= nil then
        -- The router hands the decoded path parameters over; the other locations are read from the request.
        raw[location] = location == "path" and supplied.path or READERS[location](request, list)
      end
    end
    local ok, built = root:build(raw, build_options)
    if not ok then return problems.from_error(failure(built), problem_options) end
    for location in pairs(names) do supplied[location] = built[location] end
    return nil
  end

  local function read_content(request)
    local media = request.fields:get("Content-Type")
    if media ~= nil then
      local parsed = request:media_type()
      if parsed == nil or parsed:essence() ~= JSON then return problems.response(415) end
    end
    local text = request:read_content()
    local value
    if text == "" then
      -- No content: the schema decides whether that is acceptable (`optional`, `default`) or a violation.
      if media == nil then value = nil else return problems.response(400, "The request content is not valid JSON.") end
    else
      if media == nil then return problems.response(415) end
      local ok, decoded = pcall(json.decode, text)
      if not ok then
        if not core.is_instance_of(decoded, json.DecodeError) then error(decoded, 0) end
        local status = DECODE_STATUS[decoded.context and decoded.context.reason] or 400
        return problems.response(status, status == 400 and "The request content is not valid JSON." or nil)
      end
      value = decoded
    end
    local ok, built = (content --[[@as hecate.schema.Schema]]):build(value, content_options)
    if not ok then return problems.from_error(failure(built), problem_options) end
    request:set_validated_content(built)
    return nil
  end

  if content == nil then return read_parameters end
  if root == nil then return read_content end
  return function(request)
    return read_parameters(request) or read_content(request)
  end
end

return input
