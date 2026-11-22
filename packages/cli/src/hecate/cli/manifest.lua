-- The project manifest `hecate.project.lua` (ADR 0009, cli-and-packaging.md): evaluated in an empty environment
-- with limits on the work it may do, then validated with `hecate.schema`.
global <const> require, load, type, tostring, ipairs, pairs, table, error, pcall

local core = require("hecate.core")
local schema = require("hecate.schema")
local sandbox = require("hecate.cli.internal.sandbox")
local constraint = require("hecate.cli.constraint")

---@class hecate.cli.ManifestContract
---@field title string
---@field version string
---@field servers? string[]

---@class hecate.cli.ManifestDoc  options of `hecate.doc.generate_project_documentation`, filled with defaults by `hecate new`
---@field guides_dir? string
---@field output_dir? string
---@field sources_dir? string
---@field package_name? string
---@field site_configuration_path? string

---@class hecate.cli.Manifest
---@field name string
---@field version? string  SemVer
---@field description? string
---@field license? string
---@field lua? string  the Lua line, for example "5.5"
---@field hecate? string  the expected Hecate line, a LuaRocks constraint
---@field dependencies? table<string, string>  rock name to LuaRocks constraint
---@field development_dependencies? table<string, string>
---@field scripts? table<string, string>  script name to a path inside the project
---@field contract? hecate.cli.ManifestContract
---@field rocks_servers? string[]
---@field doc? hecate.cli.ManifestDoc

--- Loading and validation of `hecate.project.lua`.
---@class hecate.cli.manifest
local M = {}

local text = schema.string({ min_length = 1, max_length = 4096 })
local constraints = schema.map(text)

--- The schema of the manifest. Every key not declared here is refused.
---@type hecate.schema.Schema
M.schema = schema.object({
  name = schema.string({ min_length = 1, max_length = 214, pattern = "^[a-z0-9][a-z0-9%._%-]*$" }),
  version = schema.optional(schema.string({ max_length = 256, pattern = "^%d+%.%d+%.%d+[%w%.%-%+]*$" })),
  description = schema.optional(schema.string({ max_length = 4096 })),
  license = schema.optional(text),
  lua = schema.optional(schema.string({ max_length = 16, pattern = "^%d+%.%d+$" })),
  hecate = schema.optional(text),
  dependencies = schema.optional(constraints),
  development_dependencies = schema.optional(constraints),
  scripts = schema.optional(schema.map(text)),
  contract = schema.optional(schema.object({
    title = text,
    version = text,
    servers = schema.optional(schema.array(text)),
  })),
  rocks_servers = schema.optional(schema.array(text)),
  doc = schema.optional(schema.object({
    guides_dir = schema.optional(text),
    output_dir = schema.optional(text),
    sources_dir = schema.optional(text),
    package_name = schema.optional(text),
    site_configuration_path = schema.optional(text),
  })),
})

local function fail(message, path, context)
  context = context or {}
  context.path = path
  error(core.ConfigurationError({ message = message, context = context }), 0)
end

--- Validates a manifest table. Raises `hecate.core.ConfigurationError` listing every violation as
--- `<pointer>: <message>`, with the violations in `context.violations`.
---@param value any
---@param path? string  file name used in messages (default `hecate.project.lua`)
---@return hecate.cli.Manifest manifest
function M.validate(value, path)
  path = path or "hecate.project.lua"
  if type(value) ~= "table" then fail(path .. ": the manifest must return a table", path) end
  local ok, violations = M.schema:validate(value)
  local lines = {}
  if not ok then
    for _, violation in ipairs(violations --[[@as hecate.schema.Violation[] ]]) do
      lines[#lines + 1] = "  " .. tostring(violation)
    end
  else
    -- The constraints keep the LuaRocks syntax (ADR 0009): a malformed one is refused here, not at install time.
    local function check(pointer, text)
      local parsed, err = pcall(constraint.parse, text)
      if not parsed then lines[#lines + 1] = "  " .. pointer .. ": " .. tostring((err --[[@as hecate.core.Error]]).message) end
    end
    for _, section in ipairs({ "dependencies", "development_dependencies" }) do
      for name, text in pairs(value[section] or {}) do check("/" .. section .. "/" .. name, text) end
    end
    if value.hecate then check("/hecate", value.hecate) end
    table.sort(lines)
  end
  if #lines > 0 then
    fail(path .. ": invalid manifest:\n" .. table.concat(lines, "\n"), path, { violations = (not ok) and violations or nil, problems = lines })
  end
  return value
end

--- Evaluates the text of a manifest in an empty environment (no globals, no `require`) with an instruction and
--- memory limit, then validates the table it returns. Raises `hecate.core.ConfigurationError` for a syntax error, a
--- precompiled chunk, a runtime error, a limit, a result that is not a table, or a violation.
---@param source string  the text of the file
---@param path? string  file name used in messages (default `hecate.project.lua`)
---@param limits? { instructions?: integer, kilobytes?: integer }
---@return hecate.cli.Manifest manifest
function M.parse(source, path, limits)
  path = path or "hecate.project.lua"
  local chunk, message = load(source, "=" .. path, "t", {})
  if not chunk then error(core.ConfigurationError({ message = path .. ": " .. tostring(message), context = { path = path } }), 0) end
  local ok, result = sandbox.run(chunk, limits)
  if not ok then fail(path .. ": " .. tostring(result), path) end
  return M.validate(result, path)
end

return M
