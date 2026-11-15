-- The contract lint: checks an OpenAPI 3.1 document (a table, as `openapi.build` returns it) for what a reader of the
-- contract needs: a name (`operationId`), a description, documented responses, examples, and no unused listed tag.
-- Findings are sorted (by `path`, `rule`), so equal documents give the same list; messages name rules and
-- locations, never a value of the contract.
global <const> require, type, pairs, ipairs, error, table, string

local core = require("hecate.core")

---@class hecate.openapi.Finding
---@field rule string  a stable identifier, such as `response-undocumented`
---@field severity "error"|"warning"
---@field path string  `METHOD /path`, then the location inside the operation; `tags` for the tag list
---@field message string

local lint = {}

local METHODS <const> = { get = "GET", put = "PUT", post = "POST", delete = "DELETE", options = "OPTIONS",
  head = "HEAD", patch = "PATCH", trace = "TRACE" }

local function nonempty(value)
  return type(value) == "string" and value ~= ""
end

local function has_example(media)
  if media.example ~= nil or media.examples ~= nil then return true end
  local schema = media.schema
  return type(schema) == "table" and (schema.example ~= nil or schema.examples ~= nil)
end

--- Lints one operation, appending findings to `found`.
local function operation(found, where, op, used)
  local function add(rule, severity, path, message)
    found[#found + 1] = { rule = rule, severity = severity, path = path, message = message }
  end
  if not nonempty(op.operationId) then add("operation-id-missing", "error", where, "the operation has no operationId") end
  if not nonempty(op.summary) and not nonempty(op.description) then
    add("description-missing", "warning", where, "the operation has neither a summary nor a description")
  end
  for _, tag in ipairs(op.tags or {}) do used[tag] = true end

  local responses = op.responses
  local codes, only_default = 0, true
  for code, response in pairs(type(responses) == "table" and responses or {}) do
    codes = codes + 1
    if code ~= "default" then only_default = false end
    local at = where .. " response " .. code
    if type(response) ~= "table" or not nonempty(response.description) then
      add("response-description-missing", "error", at, "the response has no description")
    end
    if type(response) == "table" and type(response.content) == "table" and code:match("^2") then
      for media_type, media in pairs(response.content) do
        if type(media) == "table" and not has_example(media) then
          add("example-missing", "warning", at .. " " .. media_type, "the response content has no example")
        end
      end
    end
  end
  if codes == 0 or (only_default and codes == 1 and responses.default and
      responses.default.description == "No response is declared for this route.") then
    add("response-undocumented", "error", where, "the route declares no response")
  end

  local body = op.requestBody
  if type(body) == "table" and type(body.content) == "table" then
    for media_type, media in pairs(body.content) do
      if type(media) == "table" and not has_example(media) then
        add("example-missing", "warning", where .. " request " .. media_type, "the request content has no example")
      end
    end
  end
end

--- Findings for `document`, sorted by `path` then `rule`. Raises `hecate.core.ArgumentError` when it is not a table.
---@param document table
---@return hecate.openapi.Finding[]
function lint.run(document)
  if type(document) ~= "table" then
    error(core.ArgumentError("hecate.openapi.lint: the document must be a table, got " .. type(document)), 0)
  end
  local found, used = {}, {}
  for path, item in pairs(type(document.paths) == "table" and document.paths or {}) do
    for method, op in pairs(type(item) == "table" and item or {}) do
      if METHODS[method] and type(op) == "table" then
        operation(found, METHODS[method] .. " " .. path, op, used)
      end
    end
  end
  for _, tag in ipairs(type(document.tags) == "table" and document.tags or {}) do
    if type(tag) == "table" and nonempty(tag.name) and not used[tag.name] then
      found[#found + 1] = { rule = "tag-unused", severity = "warning", path = "tags",
        message = ("the listed tag %q is used by no operation"):format(tag.name) }
    end
  end
  table.sort(found, function(a, b)
    if a.path ~= b.path then return a.path < b.path end
    if a.rule ~= b.rule then return a.rule < b.rule end
    return a.message < b.message
  end)
  return found
end

return lint
