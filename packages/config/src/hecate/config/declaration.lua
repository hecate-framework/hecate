-- The keys that every configuration has (`logging`, `limits`, `errors`, `requests`, `server`) and the walk of a schema that derives environment
-- variables and checks paths (configuration.md, "Logging keys", "The limit on nesting depth", "Environment variables").
global <const> require, type, pairs, ipairs, table, string, getmetatable, error

local core = require("hecate.core")
local schema = require("hecate.schema")

---@class hecate.config.declaration
local M = {}

--- The eight severities of RFC 5424, section 6.2.1, most urgent first (the names of `hecate.log.Severity`; `config`
--- cannot depend on `log`, a test keeps the lists equal).
---@type string[]
M.SEVERITIES = { "emergency", "alert", "critical", "error", "warning", "notice", "informational", "debug" }

--- The highest `limits.max_depth` (OQ-92): the cap of `hecate.json` (`json.MAX_DEPTH_CEILING`), repeated because
--- `config` does not depend on `json`; a test compares the two.
M.MAX_DEPTH_CEILING = 1000

local FRAMEWORK = { logging = true, limits = true, errors = true, requests = true, server = true }

--- The framework properties declared by every configuration.
---@return table<string, hecate.schema.Schema>
function M.framework_properties()
  local severity = schema.enumeration(M.SEVERITIES)
  return {
    logging = schema.default(schema.object({
      severity = schema.default(severity, "informational"),
      severities = schema.default(schema.map(severity), {}),
      sinks = schema.default(schema.array(schema.enumeration({ "console", "json_lines", "file" })), { "console" }),
      file = schema.optional(schema.object({ path = schema.optional(schema.string({ min_length = 1 })) })),
      async = schema.default(schema.boolean(), false),
      redact = schema.default(schema.array(schema.string({ min_length = 1 })), {}),
    }), {}),
    limits = schema.default(schema.object({
      max_depth = schema.default(schema.integer({ minimum = 1, maximum = M.MAX_DEPTH_CEILING }), M.MAX_DEPTH_CEILING),
    }), {}),
    errors = schema.default(schema.object({
      expose_details = schema.default(schema.boolean(), false),
    }), {}),
    -- `schema.number` is finite (it refuses NaN and infinity); the timeout is read from the environment (The Twelve-Factor App, III).
    server = schema.default(schema.object({
      grace_timeout = schema.default(schema.number({ minimum = 0 }), 30),
    }), {}),
    requests = schema.default(schema.object({
      inputs = schema.default(schema.enumeration({ "strict", "lax" }), "strict"),
    }), {}),
  }
end

--- Builds the root schema of a configuration from the properties of the application.
---@param properties table<string, hecate.schema.Schema>
---@return hecate.schema.Schema
function M.root(properties)
  local all = M.framework_properties()
  for name, property in pairs(properties) do all[name] = property end
  return schema.object(all)
end

--- Checks the `properties` option.
---@param properties any
function M.check_properties(properties)
  if type(properties) ~= "table" or getmetatable(properties) ~= nil then
    error(core.ArgumentError("config.load: option properties must be a table of schemas, got " .. type(properties)), 3)
  end
  for name, property in pairs(properties) do
    if type(name) ~= "string" or name == "" then
      error(core.ArgumentError("config.load: option properties: property names must be non-empty strings"), 3)
    end
    if FRAMEWORK[name] then
      error(core.ArgumentError(("config.load: option properties: %s is a key of the framework and cannot be declared"):format(name)), 3)
    end
    if not schema.is_schema(property) then
      error(core.ArgumentError(("config.load: option properties: %s is not a schema"):format(name)), 3)
    end
  end
end

local WRAPPERS = { optional = true, default = true, named = true, nullable = true }
local MAX_WALK_DEPTH = 16

--- One declared key.
---@class hecate.config.Node
---@field kind "object"|"map"|"leaf"
---@field schema hecate.schema.Schema  the schema without its wrappers (`optional`, `default`, `named`, `nullable`)
---@field children? table<string, hecate.config.Node>  the properties of an `object`
---@field segments string[]

--- Removes `optional`, `default`, `named` and `nullable` around a schema.
---@param s hecate.schema.Schema
---@return hecate.schema.Schema
function M.unwrap(s)
  local item = s.item
  while WRAPPERS[s.kind] and item ~= nil do
    s = item
    item = s.item
  end
  return s
end

--- Walks the declared keys.
---@param s hecate.schema.Schema
---@param segments string[]
---@param depth integer
---@return hecate.config.Node
local function walk(s, segments, depth)
  local inner = M.unwrap(s)
  if inner.kind == "object" then
    if depth >= MAX_WALK_DEPTH then
      error(core.ArgumentError(("config.load: option properties: %s is nested deeper than %d levels"):format(
        #segments == 0 and "the properties" or table.concat(segments, "."), MAX_WALK_DEPTH),
        { context = { path = table.concat(segments, ".") } }), 0)
    end
    local children = {}
    for name, property in pairs(inner.properties) do
      local path = { table.unpack(segments) }
      path[#path + 1] = name
      children[name] = walk(property, path, depth + 1)
    end
    return { kind = "object", schema = inner, children = children, segments = segments }
  elseif inner.kind == "map" then
    return { kind = "map", schema = inner, segments = segments }
  end
  return { kind = "leaf", schema = inner, segments = segments }
end

--- The declared keys of a root schema, as a tree of nodes.
---@param root hecate.schema.Schema
---@return hecate.config.Node
function M.index(root)
  return walk(root, {}, 0)
end

--- Calls `fn(node)` for every leaf of the tree, in sorted path order.
---@param node hecate.config.Node
---@param fn fun(node: hecate.config.Node)
function M.each_leaf(node, fn)
  if node.kind == "leaf" then
    fn(node)
    return
  end
  if node.kind ~= "object" then return end
  local names = {}
  for name in pairs(node.children) do names[#names + 1] = name end
  table.sort(names)
  for _, name in ipairs(names) do M.each_leaf(node.children[name], fn) end
end

--- The name of the environment variable of a path (configuration.md, "Environment variables").
---@param prefix string
---@param segments string[]
---@return string
function M.variable_name(prefix, segments)
  local joined = table.concat(segments, "__"):upper():gsub("[^%w_]", "_")
  return prefix .. "_" .. joined
end

return M
