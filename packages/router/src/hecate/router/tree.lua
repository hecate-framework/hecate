-- The compiled tree: a radix tree whose edges are whole path segments. A node holds its static children in a hash
-- table, so a step costs one table access whatever the number of routes; at most one parameter child; and the entries
-- of the routes that end at the node (`terminal`) or that end with a wildcard there (`wild`), by method.
global <const> pairs, ipairs, string, table

--- One route as the tree stores it, shared by every method of the route.
---@class hecate.router.Entry
---@field route table  the route table as declared
---@field names string[]  parameter names in order; the values are bound by position
---@field index integer  position of the route in the table

---@class hecate.router.Node
---@field static? table<string, hecate.router.Node>
---@field param? hecate.router.Node
---@field terminal? table<string, hecate.router.Entry>
---@field wild? table<string, hecate.router.Entry>

--- Insertion and lookup in the compiled tree.
---@class hecate.router.trees
local tree = {}

---@return hecate.router.Node
function tree.new() return {} end

--- Adds `entry` for `method` under the segments of `parsed`. Returns the entry that already serves the same method at
--- the same position when there is one (the table is ambiguous); the tree is then left as it was for this method, and the
--- caller abandons the whole table.
---@param root hecate.router.Node
---@param parsed hecate.router.Template
---@param method string
---@param entry hecate.router.Entry
---@return hecate.router.Entry? existing
function tree.insert(root, parsed, method, entry)
  local node = root
  local target
  for _, segment in ipairs(parsed.segments) do
    if segment.kind == "static" then
      node.static = node.static or {}
      local child = node.static[segment.value]
      if child == nil then child = {}; node.static[segment.value] = child end
      node = child
    elseif segment.kind == "parameter" then
      local child = node.param
      if child == nil then child = {}; node.param = child end
      node = child
    else
      node.wild = node.wild or {}
      target = node.wild
    end
  end
  target = target or node.terminal
  if target == nil then target = {}; node.terminal = target end
  local existing = target[method]
  if existing ~= nil then return existing end
  target[method] = entry
  return nil
end

local function find(map, method, head)
  local entry = map[method]
  if entry == nil and head and method == "HEAD" then entry = map.GET end
  return entry
end

--- The value of a wildcard: the remaining segments joined by `/`. A segment that is empty or whose decoded text holds
--- a slash makes the wildcard refuse the path, so that an encoded slash can not smuggle a separator (or a dot segment)
--- past the resolution of dot segments.
local function rest_of(segments, i, n)
  local first = segments[i]
  if first == "" or string.find(first, "/", 1, true) then return nil end
  if i == n then return first end
  for j = i + 1, n do
    local segment = segments[j]
    if segment == "" or string.find(segment, "/", 1, true) then return nil end
  end
  return table.concat(segments, "/", i, n)
end

--- Walks the tree in the order static, parameter, wildcard, backtracking when a branch ends without serving `method`.
--- With `set`, nothing is returned: every method served at a position the path reaches is added to `set` (the `Allow`
--- field of a 405).
---@param node hecate.router.Node
---@param segments string[]
---@param i integer  index of the next segment
---@param n integer  number of segments
---@param values string[]  receives the parameter values by position
---@param depth integer  number of values bound so far
---@param method string
---@param head boolean  whether `HEAD` falls back to `GET`
---@param set? table<string, true>
---@return hecate.router.Entry?
local function walk(node, segments, i, n, values, depth, method, head, set)
  if i > n then
    local terminal = node.terminal
    if terminal then
      if set == nil then return find(terminal, method, head) end
      for served in pairs(terminal) do set[served] = true end
    end
    return nil
  end
  local segment = segments[i]
  local static = node.static
  if static then
    local child = static[segment]
    if child then
      local found = walk(child, segments, i + 1, n, values, depth, method, head, set)
      if found then return found end
    end
  end
  local param = node.param
  if param and segment ~= "" then
    values[depth + 1] = segment
    local found = walk(param, segments, i + 1, n, values, depth + 1, method, head, set)
    if found then return found end
  end
  local wild = node.wild
  if wild then
    local value = rest_of(segments, i, n)
    if value then
      values[depth + 1] = value
      if set == nil then return find(wild, method, head) end
      for served in pairs(wild) do set[served] = true end
    end
  end
  return nil
end

--- Finds the entry that serves `method` for the segments, or nil. `values` receives the parameter values.
---@param root hecate.router.Node
---@param segments string[]
---@param method string
---@param head boolean
---@param values string[]
---@return hecate.router.Entry?
function tree.find(root, segments, method, head, values)
  return walk(root, segments, 1, #segments, values, 0, method, head, nil)
end

--- Collects the methods served at every position the segments reach.
---@param root hecate.router.Node
---@param segments string[]
---@return table<string, true> set
function tree.methods(root, segments)
  local set = {}
  walk(root, segments, 1, #segments, {}, 0, "", false, set)
  return set
end

return tree
