-- Validation and coercion of the inputs of a request by the schemas of its route (http-and-routing.md "Route
-- declaration", schemas-and-contracts.md "Coercion"). Every schema is resolved once, when the dispatcher is composed;
-- a request then pays one `build` per declared input and nothing at all for a route that declares none.
global <const> require, error, pcall, ipairs, pairs, next, table, string

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
-- The `source` member of a 422 entry per location of `parameters` (OQ-114 (1)); the content is `content`.
local SOURCES <const> = { path = "path", query = "query", fields = "header", cookies = "cookie" }

--- The raw texts of one location, for the declared names only (an undeclared query parameter, header field or cookie is
--- never exposed). A name sent once is its text, a repeated one a list of texts (schema `array` reads both).
local READERS <const> = {
  ---@param parsed hecate.http.Form?  the parsed query, nil when the request has none
  ---@param names string[]
  query = function(parsed, names)
    local raw = {}
    if parsed == nil then return raw end
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

--- RFC 6901, section 3: `~` becomes `~0`, then `/` becomes `~1`.
local function escape_token(token)
  return (token:gsub("~", "~0"):gsub("/", "~1"))
end

--- The violations of the parameters, each with its `source` and a pointer relative to the value inside that source (the
--- schema of the whole points at `/query/limit`; the entry says `source = "query"`, `pointer = "/limit"`).
local function with_sources(violations)
  local mapped = {}
  for i, violation in ipairs(violations) do
    local location, rest = string.match(violation.path, "^/([^/]*)(.*)$")
    mapped[i] = { path = rest or violation.path, code = violation.code, message = violation.message,
      source = SOURCES[location] }
  end
  return mapped
end

--- The violations (`additional_properties`, source `query`) of the names of `parsed` that are not in `declared`, one per
--- name, in order of appearance, at most `problems.MAX_ERRORS`. Nil when there is none. The values are never read.
local function undeclared_names(parsed, declared)
  local found, seen
  for name in parsed:pairs() do
    if declared[name] == nil then
      seen = seen or {}
      if not seen[name] then
        seen[name] = true
        found = found or {}
        found[#found + 1] = { path = "/" .. escape_token(name), code = "additional_properties", source = "query",
          message = "the query parameter is not declared by the route" }
        if #found >= problems.MAX_ERRORS then break end
      end
    end
  end
  return found
end

--- Compiles the parameters of an entry: the schema of the whole (`path`, `query`, `fields`, `cookies`, each declared
--- location an `object`, so a violation of the whole points at `/query/limit`; `with_sources` splits it) and, per location, the names to read. Nil when the
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

--- Options of `input.compile`.
---@class hecate.kernel.input.Options
---@field expose_details? boolean  see `hecate.kernel.problems.Options`
---@field strict? boolean  refuse a request that carries an undeclared query parameter (`inputs = "strict"`, OQ-114 (8)); default false here, the dispatcher passes its policy

--- Builds the step of an entry that reads, coerces and validates its inputs, or nil when it declares none (such a route
--- pays nothing). The step takes the request and returns nil when the inputs conform (it has then set
--- `request.parameters.<location>` and `request.content`) or the problem details response to answer with: `422` for
--- violations (`problems.from_error` with `input = true`), `400` for malformed content, `415` for a `Content-Type` other
--- than `application/json`, `413` for content over the limit (a `ContentError` of the reader is raised, the guard maps it).
--- It suspends while it reads the content.
---
--- Raises `RouteDeclarationError` (`unsupported_content_type`) for content declared only for another media type.
---@param entry hecate.kernel.RouteEntry
---@param options? hecate.kernel.input.Options
---@return (fun(request: hecate.http.Request): hecate.http.Response?)?
function input.compile(entry, options)
  local root, names = compile_parameters(entry)
  local content = compile_content(entry)
  local strict = options ~= nil and options.strict == true
  local declared_query = {}
  if names ~= nil and names.query ~= nil then
    for _, name in ipairs(names.query) do declared_query[name] = true end
  end
  local problem_options = { input = true, expose_details = options ~= nil and options.expose_details or nil }
  if root == nil and content == nil then
    if not strict then return nil end
    -- Strict and no declared input: the only step is the refusal of undeclared query parameters, and a request without a
    -- query string passes it with one comparison, no allocation.
    return function(request)
      local text = request.query
      if text == nil or text == "" then return nil end
      local found = undeclared_names(form.parse_urlencoded(text), declared_query)
      if found ~= nil then return problems.from_error(failure(found), problem_options) end
      return nil
    end
  end
  -- Defaults apply to a text input whatever the method; the content schema alone follows the method (PATCH, OQ-50).
  local content_options = entry.method == "PATCH" and { method = "PATCH" } or nil
  local build_options = { coerce = true }

  local function read_parameters(request)
    ---@cast root hecate.schema.Schema
    ---@cast names table<string, string[]>
    local raw, supplied = {}, request.parameters
    -- The query component is `application/x-www-form-urlencoded` text (WHATWG URL Standard, section 5.1), parsed once.
    local parsed
    if (strict or names.query ~= nil) and request.query ~= nil and request.query ~= "" then
      parsed = form.parse_urlencoded(request.query)
      if strict then
        -- Undeclared names are refused first, before any coercion: one 422 that names them (OQ-114 (8)).
        local found = undeclared_names(parsed, declared_query)
        if found ~= nil then return problems.from_error(failure(found), problem_options) end
      end
    end
    for _, location in ipairs(LOCATIONS) do
      local list = names[location] --[[@as string[]?]]
      if list ~= nil then
        -- The router hands the decoded path parameters over; the other locations are read from the request.
        if location == "path" then
          raw[location] = supplied.path
        elseif location == "query" then
          raw[location] = READERS.query(parsed, list)
        else
          raw[location] = READERS[location](request, list)
        end
      end
    end
    local ok, built = root:build(raw, build_options)
    if not ok then return problems.from_error(failure(with_sources(built)), problem_options) end
    for location in pairs(names) do supplied[location] = built[location] end
    return nil
  end

  local function read_content(request)
    local media = request.fields:get("Content-Type")
    -- RFC 9110, section 5.3: a field that is not a list may not be repeated; two `Content-Type` lines are ambiguous (a
    -- proxy and the server may read different ones), so the request is refused instead of guessing.
    if media ~= nil and request.fields:get_all("Content-Type")[2] ~= nil then
      return problems.response(400, "The request has more than one Content-Type field.")
    end
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
    if not ok then
      local mapped = {}
      for i, violation in ipairs(built) do
        mapped[i] = { path = violation.path, code = violation.code, message = violation.message, source = "content" }
      end
      return problems.from_error(failure(mapped), problem_options)
    end
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
