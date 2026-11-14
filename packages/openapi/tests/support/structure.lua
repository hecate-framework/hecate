-- A structural self-check of an OpenAPI 3.1 document, independent of `hecate.openapi`: it reads only the decoded
-- document. It is NOT a validator of the official JSON Schema (that needs `$dynamicRef`, `unevaluatedProperties`,
-- `if`/`then`/`else`, `format` and `pattern`, which no checker of this repository implements, OQ-130). It checks what
-- `openapi.build` emits: the fixed fields of OpenAPI 3.1, section 4.8 (the Objects), restricted to the objects the
-- assembly produces, with the allowed and required fields of each object written in `OBJECTS` and cross-checked against
-- the official schema by `conformance_test.lua` whenever the pinned schema is downloaded.
local M = {}

--- Fixed fields per object (OpenAPI 3.1, 4.8): `allowed` is the whole set of the official schema (`unevaluatedProperties`
--- is false there: the only other keys are specification extensions `x-...`, section 4.8.1), `required` its `required`.
M.OBJECTS = {
  document = { def = nil, required = { "openapi", "info" },
    allowed = { "openapi", "info", "jsonSchemaDialect", "servers", "paths", "webhooks", "components", "security", "tags", "externalDocs" } },
  info = { def = "info", required = { "title", "version" },
    allowed = { "title", "summary", "description", "termsOfService", "contact", "license", "version" } },
  contact = { def = "contact", required = {}, allowed = { "name", "url", "email" } },
  license = { def = "license", required = { "name" }, allowed = { "name", "identifier", "url" } },
  server = { def = "server", required = { "url" }, allowed = { "url", "description", "variables" } },
  external_docs = { def = "external-documentation", required = { "url" }, allowed = { "description", "url" } },
  tag = { def = "tag", required = { "name" }, allowed = { "name", "description", "externalDocs" } },
  path_item = { def = "path-item", required = {},
    allowed = { "$ref", "summary", "description", "get", "put", "post", "delete", "options", "head", "patch", "trace", "servers", "parameters" } },
  operation = { def = "operation", required = {},
    allowed = { "tags", "summary", "description", "externalDocs", "operationId", "parameters", "requestBody", "responses",
      "callbacks", "deprecated", "security", "servers" } },
  parameter = { def = "parameter", required = { "name", "in" },
    allowed = { "name", "in", "description", "required", "deprecated", "schema", "content" } },
  request_body = { def = "request-body", required = { "content" }, allowed = { "description", "content", "required" } },
  media_type = { def = "media-type", required = {}, allowed = { "schema", "encoding" } },
  response = { def = "response", required = { "description" }, allowed = { "description", "headers", "content", "links" } },
  components = { def = "components", required = {},
    allowed = { "schemas", "responses", "parameters", "examples", "requestBodies", "headers", "securitySchemes", "links", "callbacks", "pathItems" } },
}

local METHODS = { get = true, put = true, post = true, delete = true, options = true, head = true, patch = true, trace = true }
local LOCATIONS = { query = true, header = true, path = true, cookie = true }

local function is_object(value) return type(value) == "table" and (next(value) == nil or type(next(value)) == "string") end

--- Checks `document`; returns the list of problems, each prefixed with its JSON Pointer-like location.
---@param document table
---@return string[]
function M.check(document)
  local problems = {}
  local function problem(where, message) problems[#problems + 1] = where .. ": " .. message end

  local function fixed(where, kind, value)
    if not is_object(value) then return problem(where, "must be an object") end
    local spec = M.OBJECTS[kind]
    local allowed = {}
    for _, name in ipairs(spec.allowed) do allowed[name] = true end
    for _, name in ipairs(spec.required) do
      if value[name] == nil then problem(where, "missing required field '" .. name .. "'") end
    end
    for name in pairs(value) do
      if not allowed[name] and not tostring(name):find("^x%-") then problem(where, "unknown field '" .. tostring(name) .. "'") end
    end
  end

  local function str(where, value, field)
    if value ~= nil and type(value) ~= "string" then problem(where .. "/" .. field, "must be a string") end
  end

  local function external_docs(where, value)
    fixed(where, "external_docs", value)
    if is_object(value) then str(where, value.url, "url"); str(where, value.description, "description") end
  end

  local function check_ref(where, node)
    -- 4.8.23 Reference Object; 4.8.24 Schema Object `$ref` into `#/components/schemas/<name>` (RFC 6901).
    if type(node) ~= "table" then return end
    for key, value in pairs(node) do
      if key == "$ref" and type(value) == "string" then
        local name = value:match("^#/components/schemas/(.+)$")
        if value:sub(1, 1) == "#" and not (name and document.components and document.components.schemas
          and document.components.schemas[(name:gsub("~1", "/"):gsub("~0", "~"))] ~= nil) then
          problem(where, "$ref '" .. value .. "' does not resolve")
        end
      elseif type(value) == "table" then
        check_ref(where .. "/" .. tostring(key), value)
      end
    end
  end

  local function check_content(where, content)
    if not is_object(content) or next(content) == nil then return problem(where, "content must be a non-empty object") end
    for media, entry in pairs(content) do
      fixed(where .. "/" .. media, "media_type", entry)
      if not media:find("^[%w!#$&^_.+*%-]+/[%w!#$&^_.+*%-]+") then problem(where, "'" .. media .. "' is not a media type") end
    end
  end

  local function check_parameters(where, list, declared)
    if type(list) ~= "table" then return problem(where, "must be an array") end
    local seen = {}
    for index, parameter in ipairs(list) do
      local at = where .. "/" .. (index - 1)
      fixed(at, "parameter", parameter)
      if is_object(parameter) then
        str(at, parameter.name, "name")
        if parameter["in"] ~= nil and not LOCATIONS[parameter["in"]] then problem(at, "'in' must be query, header, path or cookie") end
        if parameter.required ~= nil and type(parameter.required) ~= "boolean" then problem(at, "required must be a boolean") end
        if (parameter.schema ~= nil) == (parameter.content ~= nil) then problem(at, "exactly one of schema and content is required") end
        if parameter["in"] == "path" then
          if parameter.required ~= true then problem(at, "a path parameter must have required = true (4.8.12.2)") end
          if type(parameter.name) == "string" then declared[parameter.name] = true end
        end
        local identity = tostring(parameter.name) .. "\0" .. tostring(parameter["in"])
        if seen[identity] then problem(at, "duplicate parameter (name, in)") end
        seen[identity] = true
      end
    end
  end

  fixed("#", "document", document)
  if type(document.openapi) ~= "string" or not document.openapi:find("^3%.1%.%d+") then problem("#/openapi", "must be a 3.1.x version string") end
  if is_object(document.info) then
    fixed("#/info", "info", document.info)
    str("#/info", document.info.title, "title"); str("#/info", document.info.version, "version")
    if document.info.contact ~= nil then fixed("#/info/contact", "contact", document.info.contact) end
    if document.info.license ~= nil then
      fixed("#/info/license", "license", document.info.license)
      if is_object(document.info.license) and document.info.license.identifier ~= nil and document.info.license.url ~= nil then
        problem("#/info/license", "identifier and url are mutually exclusive")
      end
    end
  else
    problem("#/info", "must be an object")
  end
  for index, server in ipairs(document.servers or {}) do
    fixed("#/servers/" .. (index - 1), "server", server)
    if is_object(server) then str("#/servers/" .. (index - 1), server.url, "url") end
  end
  if document.externalDocs ~= nil then external_docs("#/externalDocs", document.externalDocs) end
  local tag_names = {}
  for index, tag in ipairs(document.tags or {}) do
    local at = "#/tags/" .. (index - 1)
    fixed(at, "tag", tag)
    if is_object(tag) then
      str(at, tag.name, "name")
      if type(tag.name) == "string" then
        if tag_names[tag.name] then problem(at, "duplicate tag name (4.8.22)") end
        tag_names[tag.name] = true
      end
      if tag.externalDocs ~= nil then external_docs(at .. "/externalDocs", tag.externalDocs) end
    end
  end
  if document.components ~= nil then
    fixed("#/components", "components", document.components)
    for name in pairs((is_object(document.components) and document.components.schemas) or {}) do
      if not name:find("^[%w%._%-]+$") then problem("#/components/schemas", "key '" .. name .. "' does not match ^[a-zA-Z0-9._-]+$ (4.8.7)") end
    end
  end

  local operation_ids = {}
  for path, item in pairs(document.paths or {}) do
    local at = "#/paths/" .. path
    if path:sub(1, 1) ~= "/" then problem(at, "a path must start with '/' (4.8.8)") end
    fixed(at, "path_item", item)
    if is_object(item) then
      local template = {}
      for name in path:gmatch("{([^{}]*)}") do template[name] = true end
      local shared = {}
      if item.parameters ~= nil then check_parameters(at .. "/parameters", item.parameters, shared) end
      for key, operation in pairs(item) do
        if METHODS[key] then
          local where = at .. "/" .. key
          fixed(where, "operation", operation)
          if is_object(operation) then
            local declared = {}
            for name in pairs(shared) do declared[name] = true end
            if operation.parameters ~= nil then check_parameters(where .. "/parameters", operation.parameters, declared) end
            for name in pairs(template) do
              if not declared[name] then problem(where, "path parameter '" .. name .. "' of the template is not declared") end
            end
            for name in pairs(declared) do
              if not template[name] then problem(where, "path parameter '" .. name .. "' is not in the path template") end
            end
            if operation.operationId ~= nil then
              str(where, operation.operationId, "operationId")
              if operation_ids[operation.operationId] then problem(where, "duplicate operationId (4.8.10)") end
              operation_ids[operation.operationId] = true
            end
            for _, tag in ipairs(operation.tags or {}) do
              if type(tag) ~= "string" then problem(where .. "/tags", "must contain strings") end
            end
            if operation.externalDocs ~= nil then external_docs(where .. "/externalDocs", operation.externalDocs) end
            if operation.requestBody ~= nil then
              fixed(where .. "/requestBody", "request_body", operation.requestBody)
              if is_object(operation.requestBody) then
                check_content(where .. "/requestBody/content", operation.requestBody.content)
                if operation.requestBody.required ~= nil and type(operation.requestBody.required) ~= "boolean" then
                  problem(where .. "/requestBody", "required must be a boolean")
                end
              end
            end
            -- Every route documents at least one response (the invariant of `hecate.openapi`; the official schema requires one
            -- of `default` or a status code only when `responses` is present).
            if not is_object(operation.responses) or next(operation.responses) == nil then
              problem(where .. "/responses", "an operation must document at least one response")
            else
              for code, response in pairs(operation.responses) do
                local response_at = where .. "/responses/" .. code
                if not (code == "default" or code:find("^[1-5]%d%d$") or code:find("^[1-5]XX$")) then
                  problem(response_at, "not a status code, a range or 'default' (4.8.16)")
                end
                fixed(response_at, "response", response)
                if is_object(response) then
                  if type(response.description) ~= "string" then problem(response_at, "description is mandatory (4.8.17)") end
                  if response.content ~= nil then check_content(response_at .. "/content", response.content) end
                end
              end
            end
          end
        end
      end
    end
  end
  check_ref("#", document)
  return problems
end

return M
