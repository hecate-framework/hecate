-- The compiled tree: a radix tree whose edges are whole path segments. A node holds its static children in a hash
-- table, so a static step costs one table access whatever the number of routes; its affixed children in a list scanned
-- one by one (longest text first); at most one parameter child; and the entries
-- of the routes that end at the node (`terminal`) or that end with a wildcard there (`wild`), by method.
global <const> pairs, ipairs, string, table

--- One route as the tree stores it, shared by every method of the route.
---@class hecate.router.Entry
---@field route table  the route table as declared
---@field names string[]  parameter names in order; the values are bound by position
---@field index integer  position of the route in the table
---@field segments hecate.router.TemplateSegment[]  the segments of the parsed template, to detect ambiguous tables

---@class hecate.router.Node
---@field static? table<string, hecate.router.Node>
---@field affixed? hecate.router.Affixed[]  parameters with literal text around them, longest text first
---@field param? hecate.router.Node
---@field terminal? table<string, hecate.router.Entry>
---@field wild? table<string, hecate.router.Entry>

---@class hecate.router.Affixed
---@field prefix string
---@field suffix string
---@field node hecate.router.Node

--- Insertion and lookup in the compiled tree.
---@class hecate.router.trees
local tree = {}

---@return hecate.router.Node
function tree.new() return {} end

local function starts(text, head) return string.sub(text, 1, #head) == head end
local function ends(text, tail) return tail == "" or string.sub(text, -#tail) == tail end

--- Whether one non-empty segment can match two affixed expressions: one prefix starts the other and one suffix ends
--- the other (then the longer prefix, any text and the longer suffix is such a segment).
local function affixes_overlap(a, b)
  return (starts(a.prefix, b.prefix) or starts(b.prefix, a.prefix)) and (ends(a.suffix, b.suffix) or ends(b.suffix, a.suffix))
end

--- Whether the request segment `text` can match the template segment `segment` (not a wildcard).
local function segment_matches(segment, text)
  if segment.kind == "static" then return segment.value == text end
  if text == "" then return false end
  if segment.kind == "parameter" then return true end
  return #text > #segment.prefix + #segment.suffix and starts(text, segment.prefix) and ends(text, segment.suffix)
end

--- Whether a wildcard can take the template segments `segments[i..]`: at least one, and none that is empty or holds a
--- slash (see `rest_of`). Parameters never match an empty segment and stay one segment.
local function wildcard_takes(segments, i)
  if segments[i] == nil then return false end
  for j = i, #segments do
    local segment = segments[j]
    if segment.kind == "static" and (segment.value == "" or string.find(segment.value, "/", 1, true)) then return false end
  end
  return true
end

--- Whether some request path matches both `a[i..]` and `b[j..]` (the segments before are matched by both).
local function templates_overlap(a, i, b, j)
  local x, y = a[i], b[j]
  if x == nil or y == nil then return x == nil and y == nil end
  if x.kind == "wildcard" then return y.kind == "wildcard" or wildcard_takes(b, j) end
  if y.kind == "wildcard" then return wildcard_takes(a, i) end
  local next_a, next_b = i + 1, j + 1
  if x.kind == "static" then return segment_matches(y, x.value) and templates_overlap(a, next_a, b, next_b) end
  if y.kind == "static" then return segment_matches(x, y.value) and templates_overlap(a, next_a, b, next_b) end
  if x.kind == "affixed" and y.kind == "affixed" and not affixes_overlap(x, y) then return false end
  return templates_overlap(a, next_a, b, next_b)
end

--- The first entry under `node` that serves `method` for a path that the template `segments[i..]` also matches.
local function overlapping_entry(node, segments, i, method)
  for _, map in pairs({ terminal = node.terminal, wild = node.wild }) do
    local entry = map[method]
    if entry and templates_overlap(segments, i, entry.segments, i) then return entry end
  end
  for _, child in pairs(node.static or {}) do
    local entry = overlapping_entry(child, segments, i, method)
    if entry then return entry end
  end
  for _, candidate in ipairs(node.affixed or {}) do
    local entry = overlapping_entry(candidate.node, segments, i, method)
    if entry then return entry end
  end
  return node.param and overlapping_entry(node.param, segments, i, method) or nil
end

--- Adds `entry` for `method` under the segments of `parsed`. Returns the entry that already serves the same method for
--- the same paths when there is one (the table is ambiguous): at the same position, or under an affixed sibling of the
--- same text length that can match the same segment, where precedence can not choose. The caller then abandons the
--- whole table, so the tree may be left with empty nodes.
---@param root hecate.router.Node
---@param parsed hecate.router.Template
---@param method string
---@param entry hecate.router.Entry
---@return hecate.router.Entry? existing
function tree.insert(root, parsed, method, entry)
  local node = root
  local target
  for position, segment in ipairs(parsed.segments) do
    if segment.kind == "static" then
      node.static = node.static or {}
      local child = node.static[segment.value]
      if child == nil then child = {}; node.static[segment.value] = child end
      node = child
    elseif segment.kind == "affixed" then
      local list = node.affixed
      if list == nil then list = {}; node.affixed = list end
      local child
      local size = #segment.prefix + #segment.suffix
      for _, candidate in ipairs(list) do
        if candidate.prefix == segment.prefix and candidate.suffix == segment.suffix then
          child = candidate.node
        elseif #candidate.prefix + #candidate.suffix == size and affixes_overlap(candidate, segment) then
          -- Precedence orders affixed siblings by text length only; of two that can match one segment with the same
          -- length, neither has precedence, so a path both routes match is ambiguous.
          local other = overlapping_entry(candidate.node, parsed.segments, position + 1, method)
          if other then return other end
        end
      end
      if child == nil then
        child = {}
        list[#list + 1] = { prefix = segment.prefix, suffix = segment.suffix, node = child }
        -- the longest literal text first: `{x}.json` before `{x}`-like shorter ones; a stable order for equal lengths
        table.sort(list, function(a, b)
          local la, lb = #a.prefix + #a.suffix, #b.prefix + #b.suffix
          if la ~= lb then return la > lb end
          if a.prefix ~= b.prefix then return a.prefix < b.prefix end
          return a.suffix < b.suffix
        end)
      end
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

--- Walks the tree in the order static, affixed parameter, parameter, wildcard, backtracking when a branch ends without serving `method`.
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
  local affixed = node.affixed
  if affixed then
    local size = #segment
    for k = 1, #affixed do
      local candidate = affixed[k]
      local prefix, suffix = candidate.prefix, candidate.suffix
      local lp, ls = #prefix, #suffix
      if size > lp + ls
        and (lp == 0 or string.sub(segment, 1, lp) == prefix)
        and (ls == 0 or string.sub(segment, size - ls + 1) == suffix) then
        values[depth + 1] = string.sub(segment, lp + 1, size - ls)
        local found = walk(candidate.node, segments, i + 1, n, values, depth + 1, method, head, set)
        if found then return found end
      end
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
