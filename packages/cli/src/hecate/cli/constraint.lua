-- LuaRocks versions and dependency constraints, as `hecate.project.lua` and `hecate.lock` use them (ADR 0009: the
-- constraints keep the LuaRocks syntax unchanged). A port of the rules of LuaRocks 3.13 (`luarocks.core.vers` and
-- `luarocks.queries`), pure Lua, so that the CLI can compare a version with a constraint without starting LuaRocks.
-- The odd corners are kept on purpose: the CLI must agree with what LuaRocks would install.
global <const> require, tonumber, ipairs, error, type, math

local core = require("hecate.core")

---@class hecate.cli.Version
---@field string string  the text, trimmed
---@field revision? integer  the number after the last `-`, absent when the text has none
---@field [integer] number  the components

---@class hecate.cli.Constraint
---@field op string  one of `==`, `~=`, `>`, `<`, `>=`, `<=`, `~>`
---@field version hecate.cli.Version
---@field text string  the version as written

--- Parsing and comparison of LuaRocks versions and constraints.
---@class hecate.cli.constraint
local M = {}

-- Words that stand for a number: development versions come after every release, pre-releases before it.
local DELTAS = { dev = 120000000, scm = 110000000, cvs = 100000000, rc = -1000, pre = -10000, beta = -100000, alpha = -1000000 }

--- Parses a version such as `1.2.3-1`, `0.3`, `1.0rc1` or `scm-1`. Never fails: a text it cannot read ends the
--- component list with 0, as LuaRocks does.
---@param text string
---@return hecate.cli.Version
function M.parse_version(text)
  local version = { string = "" } ---@type hecate.cli.Version
  local index = 1
  local value = text:match("^%s*(.*)%s*$") --[[@as string]]
  version.string = value
  local main, revision = value:match("(.*)%-(%d+)$")
  if revision then
    value = main
    version.revision = tonumber(revision)
  end
  while #value > 0 do
    local token, rest = value:match("^(%d+)[%.%-%_]*(.*)")
    if token then
      local number = tonumber(token) --[[@as number]]
      version[index] = version[index] and version[index] + number / 100000 or number
      index = index + 1
    else
      token, rest = value:match("^(%a+)[%.%-%_]*(.*)")
      if not token then
        version[index] = 0
        break
      end
      version[index] = DELTAS[token] or (token:byte() / 1000)
    end
    value = rest --[[@as string]]
  end
  return version
end

---@param a hecate.cli.Version
---@param b hecate.cli.Version
---@return boolean
local function equal(a, b)
  if #a ~= #b then return false end
  for index = 1, #a do
    if a[index] ~= b[index] then return false end
  end
  if a.revision and b.revision then return a.revision == b.revision end
  return true
end

---@param a hecate.cli.Version
---@param b hecate.cli.Version
---@return boolean
local function less(a, b)
  for index = 1, math.max(#a, #b) do
    local left, right = a[index] or 0, b[index] or 0
    if left ~= right then return left < right end
  end
  if a.revision and b.revision then return a.revision < b.revision end
  return false
end

--- Orders two versions: -1 when `a` is older than `b`, 1 when newer, 0 when neither is (the same version: a missing
--- revision matches any revision, as in LuaRocks).
---@param a string
---@param b string
---@return integer order
function M.compare(a, b)
  local left, right = M.parse_version(a), M.parse_version(b)
  if less(left, right) then return -1 end
  if less(right, left) then return 1 end
  return 0
end

-- `~>`: every component of the requested version must equal the same component of the version.
local function partial_match(version, requested)
  for index, component in ipairs(requested) do
    if component ~= (version[index] or 0) then return false end
  end
  if requested.revision then return requested.revision == version.revision end
  return true
end

local OPERATORS = {
  ["=="] = "==", ["~="] = "~=", [">"] = ">", ["<"] = "<", [">="] = ">=", ["<="] = "<=", ["~>"] = "~>",
  [""] = "==", ["="] = "==", ["!="] = "~=",
}

--- Parses a constraint string such as `~> 0.3`, `>= 1.0, < 2.0`, `1.2` (an exact version) or `!= 2.0`. Raises
--- `hecate.core.ArgumentError` naming the part that is wrong.
---@param text string
---@return hecate.cli.Constraint[] constraints  all of which must hold; empty for an empty text
function M.parse(text)
  local constraints, input = {}, text
  while #input > 0 do
    local _, operator, version_text, rest = input:match("^(@?)([<>=~!]*)%s*([%w%.%_%-]+)[%s,]*(.*)")
    if operator == nil then
      if input:match("^[%s,]*$") then break end
      error(core.ArgumentError("cannot read a version constraint in '" .. text .. "' (for example '~> 0.3', '>= 1.0, < 2.0')", { context = { constraint = text } }), 0)
    end
    local op = OPERATORS[operator]
    if not op then
      error(core.ArgumentError("unknown constraint operator '" .. operator .. "' in '" .. text .. "' (use ==, ~=, >, <, >=, <= or ~>)", { context = { constraint = text } }), 0)
    end
    constraints[#constraints + 1] = { op = op, version = M.parse_version(version_text), text = version_text }
    input = rest
  end
  return constraints
end

--- Whether `version` satisfies every constraint (a string, or the list `parse` returns).
---@param version string
---@param constraints string|hecate.cli.Constraint[]
---@return boolean
function M.satisfies(version, constraints)
  if type(constraints) == "string" then constraints = M.parse(constraints) end
  local parsed = M.parse_version(version)
  for _, constraint in ipairs(constraints) do
    local wanted, op, ok = constraint.version, constraint.op, true
    if op == "==" then ok = equal(parsed, wanted)
    elseif op == "~=" then ok = not equal(parsed, wanted)
    elseif op == ">" then ok = less(wanted, parsed)
    elseif op == "<" then ok = less(parsed, wanted)
    elseif op == ">=" then ok = not less(parsed, wanted)
    elseif op == "<=" then ok = not less(wanted, parsed)
    elseif op == "~>" then ok = partial_match(parsed, wanted)
    end
    if not ok then return false end
  end
  return true
end

return M
