-- The validation core of hecate.schema: the state of a call (fail-fast mode, path stack, nesting guard, work budget,
-- memoisation of unions), the compound constructors that read it, and the methods that run a compiled schema
-- (`validate`, `coerce`, `build`, `represent`, `check`).
-- Internal to `hecate.schema`: not public API. `schema.lua` and the other `internal/` modules require it.
--
-- The state is a set of upvalue locals shared by every function below: it stays in this one module so that the hot
-- paths read it without an indirection.
---@diagnostic disable: invisible -- the `package` fields of `Schema` are shared by the internal modules of this package
global <const> require, getmetatable, type, pairs, ipairs, next, table, string, math, error, tostring

local core = require("hecate.core")
local json = require("hecate.json")
local violation_module = require("hecate.schema.violation")
local model = require("hecate.schema.internal.model")
local json_values = require("hecate.schema.internal.json_values")

local Violation = violation_module.Violation
local escape_token = violation_module.escape_token
---@class hecate.schema.Schema
local Schema = model.Schema
local refuse, read_options, check_range = model.refuse, model.read_options, model.check_range
local require_schema = model.require_schema
local remark, copy_value, json_equal = json_values.remark, json_values.copy_value, json_values.json_equal
local math_type = math.type
local null = json.null

--- Fail-fast mode: set while an alternative of a union is tried, only to learn whether it accepts. Validators then
--- stop at the first violation, check discriminating properties (literals) first and build no detail.
local fast = false

--- The path of the node being visited, as a stack of reference tokens (P1 of the review). A path is needed only where a
--- violation is recorded, so a visit passes `at`, the number of tokens of its own path, instead of building a string:
--- a container sets `segments[at + 1]` to the token of the child it descends into and passes `at + 1`. A token is an
--- integer (the 0-based index of an array item) or a string (a property name, already cut to `MAX_ECHO` for a map key),
--- escaped by `path_to`. Only the entries below `at` are meaningful, and a visit writes only above its own `at`, so
--- the entries of the ancestors stay valid whatever the descendants do; the stack is never cleared.
---@type (integer|string)[]
local segments = {}

--- The escaped reference token `k` of the segment stack, with its leading slash.
---@param k integer
---@return string
local function segment(k)
  local token = segments[k]
  if type(token) == "number" then return "/" .. token end
  ---@cast token string
  if token:find("[~/]") then return "/" .. escape_token(token) end -- only a token that needs it pays the two substitutions
  return "/" .. token
end

--- The JSON Pointer (RFC 6901) of the node whose path has `at` tokens, joined from the segment stack.
---@param at integer
---@return string
local function path_to(at)
  if at == 0 then return "" end
  if at == 1 then return segment(1) end
  if at == 2 then return segment(1) .. segment(2) end
  if at == 3 then return segment(1) .. segment(2) .. segment(3) end
  local parts = {}
  for k = 1, at do parts[k] = segment(k) end
  return table.concat(parts)
end

--- The path of a violation recorded by a validator or a coercer. In fail-fast mode the violations only tell that an
--- alternative does not accept (they are dropped, never reported), so no path is built: a failing alternative costs no
--- join (measured: a union whose alternatives fail was five times slower with the join).
---@param at integer
---@return string
local function where(at)
  if fast then return "" end
  return path_to(at)
end

--- A `type` violation: names the expected type and the Lua type received (`null` for `json.null`), never the value.
---@param at integer
---@param expected string
---@param out hecate.schema.RawViolation[]
---@param value any
local function type_violation(at, expected, out, value)
  local received = value == null and "null" or type(value)
  local message = ("expected %s, got %s"):format(expected, received)
  if expected == "integer" and math_type(value) == "float" and value == math.floor(value)
    and value ~= math.huge and value ~= -math.huge then
    message = message .. " (a whole float is refused; use an integer)"
  end
  out[#out + 1] = { where(at), "type", message, { expected = expected, received = received } }
end

--- Nesting guard (OQ-50). Content decoded by `json.decode` is at most `max_depth` (1000) levels deep, but a table built
--- by hand is not bounded, and a recursive schema (`named`, `of`) would recurse as deep as the value: a raw Lua stack
--- overflow, and a path that grows quadratically. Every container validator and coercer counts its nesting and, beyond
--- `MAX_DEPTH` (the same maximum as `json`), reports a `depth_limit` violation at the path where it stopped and does
--- not descend further. The counter is reset by each public entry point, so an error never leaves it stale.
local depth = 0

--- Work budget (OQ-91). A recursive `union` of containers can cost two to the power of the depth when nothing
--- discriminates its alternatives, and the depth guard does not bound that. Every container visited and every
--- alternative tried is a step; a call that spends more than `limits.max_steps` ends with a `complexity_limit`
--- violation at the path where it stopped (`context.max_steps`) and visits nothing more. One counter is shared by
--- `validate`, `coerce` and `build`, and each public entry point resets it, like `depth`.
---
--- Other internal bounds (like `max_steps`, not public API): `max_violations`, the violations kept per public call (S4: the
--- one after them is replaced by a `too_many_violations` violation and collection stops), and `max_pattern_bytes`, the
--- longest string without `max_length` that a `pattern` or a `format` is run on (S2).
local limits = { max_steps = 1000000, max_violations = 100, max_pattern_bytes = 65536 }
--- Longest property name echoed in a violation path or context (S4), in bytes.
local MAX_ECHO = 64
--- Set by `Schema:build` for a PATCH: an absent attribute means unchanged, so no default applies (OQ-88).
local without_defaults = false
--- Set by `Schema:build` with `coerce = true`: the object coercers record, per converted table, the attributes whose
--- value came from a default, so that the build does not count them as sent (OQ-93). Nil otherwise.
---@type table<table, table<string, true>>?
local defaulted = nil
local steps = 0
local budget_violation = nil -- the `complexity_limit` violation of the call in progress, once the budget is spent

--- Nesting of the detail pass of a failed union (`context.alternatives`): only the outermost one carries it.
local detailing = 0

--- Counts one step. Returns false, after leaving the `complexity_limit` violation in `out`, when the budget is spent.
---@param at integer
---@param out hecate.schema.RawViolation[]
---@return boolean
local function spend(at, out)
  if budget_violation == nil then
    steps = steps + 1
    if steps <= limits.max_steps then return true end
    budget_violation = { path_to(at), "complexity_limit", "the work needed exceeds " .. limits.max_steps .. " steps",
      { max_steps = limits.max_steps } }
  end
  if out[#out] ~= budget_violation then out[#out + 1] = budget_violation end
  return false
end

--- Memoisation of unions (OQ-91). Within one call, a union visited again on the same table node answers from what it
--- learned the first time: whether an alternative accepts it (validation) and its converted value (coercion). Work is
--- then proportional to the nodes times the unions, whatever the shape of the alternatives. Only union visits touch
--- it; only tables are keys; it is created on first use, dropped by each public entry point (like `depth`, so an error
--- never leaves it stale), and nothing is stored once the budget is spent. The work budget stays as the backstop.
---@type { verdicts: table<table, table<table, boolean>>, converted: table<table, table<table, any>> }?
local memo = nil

--- Nesting of the alternative attempts of the coercers and representers (a union trying an alternative whose result it
--- may reject). A node can be visited again only inside an attempt (the other alternative reaches the same node through
--- its own nested union) or in fail-fast mode (which is always an attempt), so the memoisation answers and stores only
--- there: a union outside any attempt, the common case, allocates nothing (P2 of the review, measured).
local attempts = 0

--- The answer of kind `kind` ("verdicts" or "converted") that the union owning `owner` stored for `node`, or nil.
---@param kind "verdicts"|"converted"
---@param owner table  identity of the union (a table it owns)
---@param node table
---@return any
local function recall(kind, owner, node)
  local store = memo
  if store == nil then return nil end
  local answers = store[kind][owner]
  if answers == nil then return nil end
  return answers[node]
end

--- Stores an answer (see `recall`); the stores and the answers table of a union are created by the first answer.
---@param kind "verdicts"|"converted"
---@param owner table
---@param node table
---@param answer any
local function remember(kind, owner, node, answer)
  local store = memo
  if store == nil then
    store = { verdicts = {}, converted = {} }
    memo = store
  end
  local answers = store[kind][owner]
  if answers == nil then
    answers = {}
    store[kind][owner] = answers
  end
  answers[node] = answer
end

--- Resets the counters of a public entry point.
local function reset_work()
  depth, steps, budget_violation, fast, detailing, memo, attempts = 0, 0, nil, false, 0, nil, 0
  without_defaults, defaulted = false, nil
end

--- Raw violations to `Violation`s; a spent budget is reported exactly once, even if the violation was collected in
--- a scratch list that was discarded.
---@param raw hecate.schema.RawViolation[]
---@return hecate.schema.Violation[]
local function to_violations(raw)
  local violations, seen = {}, false
  local max = limits.max_violations
  for _, v in ipairs(raw) do
    if #violations >= max then
      -- The list is full: this violation becomes the final marker and nothing after it is reported.
      violations[#violations + 1] = Violation(v[1], "too_many_violations",
        "more than " .. max .. " violations; the others are not reported", { max = max })
      return violations
    end
    if v ~= budget_violation or not seen then
      violations[#violations + 1] = Violation(v[1], v[2], v[3], v[4])
      seen = seen or v == budget_violation
    end
  end
  if budget_violation ~= nil and not seen and #violations < max then
    local v = budget_violation
    violations[#violations + 1] = Violation(v[1], v[2], v[3], v[4])
  end
  return violations
end

--- Tells whether `out` holds more violations than are kept (S4): the validators then stop descending. The extra one is
--- turned into the `too_many_violations` marker by `to_violations`.
---@param out hecate.schema.RawViolation[]
---@return boolean
local function overflowed(out)
  return #out > limits.max_violations
end

--- A property name as echoed in a violation (path token or context): cut to `MAX_ECHO` bytes, backing off to the start of
--- a UTF-8 sequence so that the cut never splits a character.
---@param key string
---@return string
local function echoed(key)
  if #key <= MAX_ECHO then return key end
  local cut = MAX_ECHO
  while cut > 0 do
    local b = key:byte(cut + 1)
    if b < 0x80 or b >= 0xC0 then break end
    cut = cut - 1
  end
  return key:sub(1, cut)
end

--- Wraps the function of a container (a validator or a coercer) with the nesting guard and the work budget. A
--- refused coercer returns its value unchanged (`keep`).
---@generic F: function
---@param inner F
---@param keep? boolean
---@return F
local function guarded(inner, keep)
  return function(value, at, out)
    if not spend(at, out) then
      if keep then return value end
      return
    end
    if depth >= json.DEFAULT_MAX_DEPTH then
      out[#out + 1] = { where(at), "depth_limit", "the value is nested deeper than " .. json.DEFAULT_MAX_DEPTH .. " levels",
        { max_depth = json.DEFAULT_MAX_DEPTH } }
      if keep then return value end
      return
    end
    depth = depth + 1
    local result = inner(value, at, out)
    depth = depth - 1
    return result
  end
end

--- Tells whether `validate` accepts `value`, in fail-fast mode.
---@param validate hecate.schema.Validator
---@param value any
---@param at integer
---@return boolean
local function accepts(validate, value, at)
  local previous, found = fast, {}
  fast = true
  validate(value, at, found)
  fast = previous
  return found[1] == nil and budget_violation == nil
end

--- Stops a representation (`Schema:represent`) with a `ValidationError` that carries one violation, with the code and
--- the JSON Pointer where it stopped, in `context.violations`. The message names the code only, never the pointer: a
--- pointer can hold a key supplied by a user (personal data) and the message of an error reaches the logs (OQ-120 (2)).
---@param path string  the JSON Pointer
---@param code hecate.schema.ViolationCode
---@param message string
---@param context? table
local function stop_representation(path, code, message, context)
  local v = Violation(path, code, message, context)
  error(core.ValidationError(("cannot represent: violation code '%s'; the JSON Pointer is in context.violations"):format(code),
    { context = { violations = { v } } }), 0)
end

--- Wraps a representer with the nesting guard and the work budget, the counters of validation (OQ-91, OQ-92). A cycle
--- of the object graph reaches `MAX_DEPTH` and ends here, never in a hang.
---@param inner hecate.schema.Representer
---@return hecate.schema.Representer
local function represented(inner)
  return function(value, at)
    steps = steps + 1
    if steps > limits.max_steps then
      stop_representation(path_to(at), "complexity_limit", "the work needed exceeds " .. limits.max_steps .. " steps",
        { max_steps = limits.max_steps })
    end
    if depth >= json.DEFAULT_MAX_DEPTH then
      stop_representation(path_to(at), "depth_limit", "the value is nested deeper than " .. json.DEFAULT_MAX_DEPTH .. " levels",
        { max_depth = json.DEFAULT_MAX_DEPTH })
    end
    depth = depth + 1
    local result = inner(value, at)
    depth = depth - 1
    return result
  end
end

local REJECTED = {} -- the memo answer for a plain form that an alternative does not accept
--- Tells whether `validate` accepts `value`, with a nesting count of its own (the representer is already `depth` deep).
local function accepts_apart(validate, value, at)
  local outer = depth
  depth = 0
  local ok = accepts(validate, value, at)
  depth = outer
  if budget_violation ~= nil then
    local v = budget_violation
    stop_representation(v[1], v[2], v[3], v[4])
  end
  return ok
end

--- The attributes of `value` as a table that holds nothing else (s2): a plain table (or one with a marker) is its own
--- attributes; an instance of a class or of a value class gives its own fields (`pairs`, which a value class answers from its
--- hidden fields table), never the members its class provides through `__index` (methods, prototype fields).
---@param value table
---@return table
local function attributes_of(value)
  local metatable = getmetatable(value)
  if metatable == nil or metatable.__index == nil then return value end
  local attributes = {}
  for key, member in pairs(value) do attributes[key] = member end
  return attributes
end

--- Tells whether `inner` accepts JSON null itself (through `optional`, `default` and `named` wrappers).
---@param inner hecate.schema.Schema
---@return boolean
local function accepts_null(inner)
  local current = inner
  while current.kind == "optional" or current.kind == "default" or current.kind == "named" do
    current = current.item --[[@as hecate.schema.Schema]]
  end
  return current.kind == "nullable" or current.kind == "null"
end

--- A deep copy of any Lua value that JSON can hold, in fresh tables (the representer of `any`); markers are kept.
local copy_plain
copy_plain = represented(function(value, at)
  if type(value) ~= "table" or value == null then return value end
  local copy = {}
  for key, member in pairs(value) do
    segments[at + 1] = type(key) == "string" and key or tostring(key)
    copy[key] = copy_plain(member, at + 1)
  end
  return remark(value, copy)
end)

---@class hecate.schema.internal.validation
local M = {}
M.limits = limits

--- Steps spent by the last public call (`validate`, `coerce`, `build` or `represent`), for the step-count tests: they assert
--- the growth of the work instead of a clock. Internal, not public API.
---@return integer
function M.steps() return steps end

--- Presence sets of the instances built by `Schema:build` (OQ-90): instance -> set of the property names that were sent.
--- Weak-keyed, so that the set does not keep a dead instance alive, and kept outside the instance, so that `pairs` and
--- `json.encode` see only the attributes.
local presence_sets = core.weak_table("k")

--- A cheap structural signature of a table, to bucket the candidates of a comparison: its entries (key and, for a scalar
--- member, its value; a table member counts as such), sorted. Two equal tables have the same signature. A float with an
--- integer value reads as that integer (`1` and `1.0` are equal numbers, OQ-85). One step is charged per entry; returns
--- nil when the budget is spent.
---@param tbl table
---@param at integer
---@param out hecate.schema.RawViolation[]
---@return string?
local function signature(tbl, at, out)
  local parts, n = {}, 0
  for key, member in next, tbl do
    if not spend(at, out) then return nil end
    local t = type(member)
    local text
    if t == "string" then text = "s" .. member
    elseif t == "number" then
      local whole = math.tointeger(member) -- nil for a float with a fraction, and for NaN and infinities
      text = whole and ("n" .. whole) or ("f" .. ("%.17g"):format(member))
    elseif t == "boolean" then text = member and "T" or "F"
    elseif member == null then text = "z"
    else text = "t" end
    n = n + 1
    parts[n] = (type(key) == "string" and "s" or "k") .. tostring(key) .. "\0" .. text
  end
  table.sort(parts)
  return table.concat(parts, "\1")
end

--- Index of the first item equal to an earlier one, or nil. Scalars are found by hashing (a Lua table key already reads
--- `1` and `1.0` as one key, and tells `1` from `"1"`); tables are compared pairwise, only within a bucket of equal
--- signature. Every item hashed and every comparison is one step of the work budget (S1, OQ-91); when the budget is spent
--- the `complexity_limit` violation is in `out` and nil is returned.
---@param list any[]
---@param length integer
---@param at integer
---@param out hecate.schema.RawViolation[]
---@return integer?
local function first_duplicate(list, length, at, out)
  local seen, buckets = {}, {}
  for i = 1, length do
    if not spend(at, out) then return nil end
    local item = list[i]
    if type(item) == "table" and item ~= null then
      local sig = signature(item, at, out)
      if sig == nil then return nil end
      local bucket = buckets[sig]
      if bucket == nil then
        buckets[sig] = { item }
      else
        for j = 1, #bucket do
          if not spend(at, out) then return nil end
          if json_equal(item, bucket[j]) then return i end
        end
        bucket[#bucket + 1] = item
      end
    elseif item == item then -- NaN equals nothing
      if seen[item] then return i end
      seen[item] = true
    end
  end
  return nil
end

--- Declares a sequence type with a schema for every element. Paths use 0-based indices (RFC 6901 section 4).
---@param item hecate.schema.Schema
---@param options? hecate.schema.ArrayOptions
---@return hecate.schema.Schema
function M.array(item, options)
  require_schema("array", item)
  local o = read_options("array", options, { min_items = "integer", max_items = "integer", delimiter = "string",
    unique_items = "boolean" })
  if o.delimiter == "" then refuse("array: option delimiter must not be empty", { option = "delimiter" }) end
  check_range("array", o, "min_items", "max_items")
  local min_items, max_items = o.min_items, o.max_items
  local unique_items = o.unique_items == true
  local validate_item = item.validator
  local coerce_item = item.coercer
  local delimiter = o.delimiter or ","
  local build_item = item.builder
  local builder = function(value)
    local result = {}
    for i = 1, #value do result[i] = build_item(value[i]) end
    return remark(value, result)
  end
  local represent_item = item.representer
  local representer = represented(function(value, at)
    if type(value) ~= "table" or value == null then stop_representation(path_to(at), "type", "expected array", { expected = "array" }) end
    local result = {}
    local child = at + 1
    for i = 1, #value do
      segments[child] = i - 1
      result[i] = represent_item(value[i], child)
    end
    return json.array(result) -- an empty array stays `[]`
  end)
  local coercer = guarded(function(value, at, out)
    if type(value) == "string" then
      -- OpenAPI `style: form, explode: false` (delimiter "," by default; " " and "|" for the other styles).
      local parts, start = {}, 1
      if value ~= "" then
        while true do
          local from, to = value:find(delimiter, start, true)
          if not from then parts[#parts + 1] = value:sub(start) break end
          parts[#parts + 1] = value:sub(start, from - 1)
          start = to + 1
        end
      end
      value = parts
    elseif type(value) ~= "table" or value == null then
      return value
    end
    local result = {}
    local child = at + 1
    for i = 1, #value do
      if overflowed(out) then return value end
      segments[child] = i - 1
      result[i] = coerce_item(value[i], child, out)
    end
    if #result ~= #value then return value end
    return result
  end, true)
  return Schema("array", { options = o, item = item, coercer = coercer, builder = builder, representer = representer, validator = guarded(function(value, at, out)
    if type(value) ~= "table" or value == null or json.is_object(value) then return type_violation(at, "array", out, value) end
    local length = #value
    local count = 0
    for _ in next, value do count = count + 1 end
    if count ~= length then return type_violation(at, "array", out, value) end
    if min_items and length < min_items then
      out[#out + 1] = { where(at), "min_items", "the array has fewer than " .. min_items .. " items", { min_items = min_items } }
    end
    if max_items and length > max_items then
      out[#out + 1] = { where(at), "max_items", "the array has more than " .. max_items .. " items", { max_items = max_items } }
    end
    local child = at + 1
    for i = 1, length do
      if fast and out[1] ~= nil then return end
      if overflowed(out) then return end
      segments[child] = i - 1
      validate_item(value[i], child, out)
    end
    if (fast and out[1] ~= nil) or overflowed(out) or budget_violation ~= nil then return end
    if unique_items then
      local duplicate = first_duplicate(value, length, at, out)
      if duplicate then
        out[#out + 1] = { where(at) .. "/" .. (duplicate - 1), "unique_items", "the item duplicates an earlier one",
          { index = duplicate - 1 } }
      end
    end
  end) })
end

--- Declares a product type: named properties, each with a schema. Required unless wrapped in `optional`.
--- Properties not declared are rejected (violation `additional_properties`) unless `additional_properties = true`.
---@param properties table<string, hecate.schema.Schema>
---@param options? hecate.schema.ObjectOptions
---@return hecate.schema.Schema
function M.object(properties, options)
  if type(properties) ~= "table" then refuse("object: properties must be a table, got " .. type(properties)) end
  local o = read_options("object", options, { additional_properties = "boolean" })
  local allow_additional = o.additional_properties == true
  local copy, names = {}, {}
  for name, property in pairs(properties) do
    if type(name) ~= "string" then refuse("object: property names are strings, got " .. type(name)) end
    require_schema("object", property)
    copy[name] = property
    names[#names + 1] = name
  end
  table.sort(names) -- a stable order of violations
  local count = #names
  local tokens, validators, optional = {}, {}, {}
  for i = 1, count do
    local property = copy[names[i]]
    tokens[i] = "/" .. escape_token(names[i])
    validators[i] = property.validator
    optional[i] = property.kind == "optional" or property.kind == "default"
  end
  local declared = {}
  for i = 1, count do declared[names[i]] = true end
  local coercers, defaults = {}, {}
  for i = 1, count do
    local property = copy[names[i]]
    coercers[i] = property.coercer
    if property.kind == "default" then defaults[i] = property.copy_default end
  end
  local builders = {}
  for i = 1, count do builders[i] = copy[names[i]].builder end
  -- Discriminating properties (literals, so the tag of a `tagged_union` variant) come first in fail-fast mode.
  local fast_order, literals = {}, {}
  for i = 1, count do
    if copy[names[i]].kind == "literal" then
      fast_order[#fast_order + 1] = i
      literals[#literals + 1] = i
    end
  end
  for i = 1, count do
    if copy[names[i]].kind ~= "literal" then fast_order[#fast_order + 1] = i end
  end
  --- A necessary condition for a value to conform, after coercion: it is an object whose literal properties are
  --- present and hold their constant (a text counts when it coerces to it). Costs one step per literal, no descent.
  local prefilter = function(value)
    if type(value) ~= "table" or value == null then return false end
    for _, i in ipairs(literals) do
      local member = value[names[i]]
      if member == nil then return false end
      local found = {}
      validators[i](coercers[i](member, 0, found), 0, found)
      if found[1] ~= nil then return false end
    end
    return true
  end
  local builder = function(value)
    local result = {}
    for key, member in next, value do result[key] = member end
    for i = 1, count do
      local member = value[names[i]]
      if member ~= nil then
        result[names[i]] = builders[i](member)
      elseif defaults[i] ~= nil and not without_defaults then
        result[names[i]] = builders[i](defaults[i]()) -- an absent property takes a fresh copy of its default (OQ-88)
      end
    end
    return remark(value, result)
  end
  local represent_members, nullable = {}, {}
  for i = 1, count do
    represent_members[i] = copy[names[i]].representer
    nullable[i] = accepts_null(copy[names[i]])
  end
  -- Only the declared properties are represented: an undeclared attribute never reaches a response, and neither does a
  -- member of the class (a method, a prototype field): the attributes are the fields of the instance itself (s2). A
  -- function is not JSON and is skipped. A nullable attribute that is nil on an instance made by `Schema:build` and was
  -- sent (an explicit null, OQ-90) is represented as null, so that the content round-trips; an instance that was not
  -- built has sent nothing, and its nil attributes are omitted (owner decision 2026-11-08).
  local representer = represented(function(value, at)
    if type(value) ~= "table" or value == null then stop_representation(path_to(at), "type", "expected object", { expected = "object" }) end
    local result = {}
    local attributes = attributes_of(value)
    local sent = presence_sets[value]
    for i = 1, count do
      local member = attributes[names[i]]
      if member == nil then
        if nullable[i] and sent ~= nil and sent[names[i]] then result[names[i]] = null end
      elseif type(member) ~= "function" then
        segments[at + 1] = names[i]
        result[names[i]] = represent_members[i](member, at + 1)
      end
    end
    return json.object(result) -- an empty object stays `{}`
  end)
  local coercer = guarded(function(value, at, out)
    if type(value) ~= "table" or value == null then return value end
    local result = {}
    for key, member in next, value do result[key] = member end
    for i = 1, count do
      if overflowed(out) then return result end
      local member = value[names[i]]
      if member ~= nil then
        segments[at + 1] = names[i]
        result[names[i]] = coercers[i](member, at + 1, out)
      elseif defaults[i] ~= nil and not without_defaults then
        result[names[i]] = defaults[i]() -- an absent property takes its default (never for a PATCH build)
        if defaulted ~= nil then
          local names_of = defaulted[result]
          if names_of == nil then names_of = {}; defaulted[result] = names_of end
          names_of[names[i]] = true
        end
      end
    end
    return result
  end, true)
  --- `relax`: the PATCH variant, where an absent property means unchanged (OQ-90).
  local function make_validator(relax) return guarded(function(value, at, out)
    if type(value) ~= "table" or value == null or json.is_array(value) then return type_violation(at, "object", out, value) end
    if fast then
      for k = 1, count do
        local i = fast_order[k]
        local member = value[names[i]]
        if member == nil then
          if not (relax or optional[i]) then
            out[#out + 1] = { where(at) .. tokens[i], "required", "the property is required", { property = names[i] } }
            return
          end
        else
          segments[at + 1] = names[i]
          validators[i](member, at + 1, out)
          if out[1] ~= nil then return end
        end
      end
      for key in next, value do
        if type(key) ~= "string" then
          return type_violation(at, "object", out, value)
        elseif not declared[key] and not allow_additional then
          local shown = echoed(key)
          out[#out + 1] = { where(at) .. "/" .. escape_token(shown), "additional_properties",
            "the property is not declared", { property = shown } }
          return
        end
      end
      return
    end
    for i = 1, count do
      if overflowed(out) then return end
      local member = value[names[i]]
      if member == nil then
        if not (relax or optional[i]) then
          out[#out + 1] = { where(at) .. tokens[i], "required", "the property is required", { property = names[i] } }
        end
      else
        segments[at + 1] = names[i]
        validators[i](member, at + 1, out)
      end
    end
    local extras
    for key in next, value do
      if type(key) ~= "string" then
        return type_violation(at, "object", out, value)
      elseif not declared[key] and not allow_additional then
        extras = extras or {}
        extras[#extras + 1] = key
      end
    end
    if extras then
      table.sort(extras)
      for _, key in ipairs(extras) do
        if overflowed(out) then return end
        local shown = echoed(key)
        out[#out + 1] = { where(at) .. "/" .. escape_token(shown), "additional_properties",
          "the property is not declared", { property = shown } }
      end
    end
  end) end
  return Schema("object", { options = o, properties = copy, coercer = coercer, validator = make_validator(false),
    relaxed_validator = make_validator(true), builder = builder, representer = representer, prefilter = prefilter })
end

--- Declares a dictionary type: any string keys, every value conforming to the schema `value`. Paths use the key as
--- the reference token. A table with non-string keys is not a map.
---@param value hecate.schema.Schema  the schema of every value
---@param options? hecate.schema.MapOptions
---@return hecate.schema.Schema
function M.map(value, options)
  require_schema("map", value)
  local value_schema = value
  local o = read_options("map", options, { min_properties = "integer", max_properties = "integer" })
  check_range("map", o, "min_properties", "max_properties")
  local min_properties, max_properties = o.min_properties, o.max_properties
  local validate_value, coerce_value = value_schema.validator, value_schema.coercer
  local build_value = value_schema.builder
  local builder = function(value)
    local result = {}
    for key, member in next, value do result[key] = build_value(member) end
    return remark(value, result)
  end
  local represent_value = value_schema.representer
  local representer = represented(function(value, at)
    if type(value) ~= "table" or value == null then stop_representation(path_to(at), "type", "expected object", { expected = "object" }) end
    local result = {}
    for key, member in pairs(value) do
      if type(key) == "string" then
        segments[at + 1] = echoed(key)
        result[key] = represent_value(member, at + 1)
      else
        result[key] = represent_value(member, at) -- not a property: the member is visited at the map itself
      end
    end
    return json.object(result) -- an empty map stays `{}`
  end)
  local coercer = guarded(function(value, at, out)
    if type(value) ~= "table" or value == null then return value end
    local result = {}
    local before = #out
    for key, member in next, value do
      if overflowed(out) then break end
      if type(key) == "string" then
        segments[at + 1] = echoed(key)
        result[key] = coerce_value(member, at + 1, out)
      else
        result[key] = member
      end
    end
    if #out > before and budget_violation == nil then
      -- The members were visited in `next` order, which differs from run to run, and so would the violations (and
      -- which of them the cap keeps). A failure is the rare path: it is discarded and visited again in byte order.
      for i = #out, before + 1, -1 do out[i] = nil end
      result = {}
      local keys = {}
      for key, member in next, value do
        if type(key) == "string" then keys[#keys + 1] = key else result[key] = member end
      end
      table.sort(keys)
      for _, key in ipairs(keys) do
        if overflowed(out) then break end
        segments[at + 1] = echoed(key)
        result[key] = coerce_value(value[key], at + 1, out)
      end
    end
    return result
  end, true)
  return Schema("map", { options = o, item = value_schema, coercer = coercer, builder = builder, representer = representer, validator = guarded(function(value, at, out)
    if type(value) ~= "table" or value == null or json.is_array(value) then return type_violation(at, "object", out, value) end
    local keys = {}
    for key in next, value do
      if type(key) ~= "string" then return type_violation(at, "object", out, value) end
      keys[#keys + 1] = key
    end
    table.sort(keys) -- a stable order of violations
    local count = #keys
    if min_properties and count < min_properties then
      out[#out + 1] = { where(at), "min_properties", "the object has fewer than " .. min_properties .. " properties",
        { min_properties = min_properties } }
    end
    if max_properties and count > max_properties then
      out[#out + 1] = { where(at), "max_properties", "the object has more than " .. max_properties .. " properties",
        { max_properties = max_properties } }
    end
    for i = 1, count do
      if fast and out[1] ~= nil then return end
      if overflowed(out) then return end
      segments[at + 1] = echoed(keys[i])
      validate_value(value[keys[i]], at + 1, out)
    end
  end) })
end

--- What makes `alternative` accept null, looking through the wrappers `named`, `optional` and `default`: "null",
--- "nullable", "literal" (a literal null) or "enumeration" (constants containing null), as the name of the kind and the
--- wording of the refusal; nil when none does. `any` is not looked for: it accepts null by an explicit choice.
---@param alternative hecate.schema.Schema
---@return string?
local function accepting_null(alternative)
  local current = alternative
  while current ~= nil do
    local kind = current.kind
    if kind == "null" or kind == "nullable" then return kind end
    if kind == "literal" then
      ---@diagnostic disable-next-line: undefined-field -- `options` holds whatever the constructor stored: `value` for a literal
      if current.options.value == null then return kind end
      return nil
    end
    if kind == "enumeration" then
      for _, member in ipairs(current:members()) do
        if member == null then return kind end
      end
      return nil
    end
    if kind ~= "named" and kind ~= "optional" and kind ~= "default" then return nil end
    current = current.item
  end
  return nil
end

local NULL_KIND_WORDING = {
  null = "a null schema", nullable = "a nullable schema", literal = "a literal null", enumeration = "an enumeration containing null",
}

--- Declares a sum type: a value conforms when at least one alternative accepts it (JSON Schema `anyOf`).
--- On failure one violation is reported at the union itself; the violations of every alternative are in
--- `context.alternatives`, in declaration order, for the outermost failed union only (OQ-91: a union nested in an
--- alternative, or in the fail-fast mode that decides the alternatives, has an empty list).
--- Alternatives are decided in fail-fast mode, discriminating properties first, so that a recursive union costs
--- linear work when its alternatives are discriminated (`tagged_union` always is), and the work budget bounds the rest.
--- A union must not contain null (OQ-99, OQ-100): an alternative that accepts null (`null`, `nullable`, a literal null, an
--- enumeration containing null; also under `named`, `optional` or `default`) is refused with `ArgumentError`, because `nullable` is the only way to accept null; write
--- `nullable(union(...))`. `any` is not refused: it accepts every value, null included, by an explicit choice.
---@param alternatives hecate.schema.Schema[]
---@return hecate.schema.Schema
function M.union(alternatives)
  if type(alternatives) ~= "table" or #alternatives == 0 then refuse("union: expects a non-empty list of schemas") end
  local copy, validators = {}, {}
  for i, alternative in ipairs(alternatives) do
    require_schema("union", alternative)
    local accepted = accepting_null(alternative)
    if accepted ~= nil then
      refuse(("union: alternative %d is %s, and a union must not contain null: nullable is the only way to accept "
        .. "null, so wrap the union in nullable(union(...)) instead"):format(i, NULL_KIND_WORDING[accepted]), { alternative = i, kind = accepted })
    end
    copy[i] = alternative
    validators[i] = alternative.validator
  end
  local count = #copy
  --- The alternatives a value may match: those whose cheap prefilter does not rule it out.
  local function candidates(value)
    local list = {}
    for i = 1, count do
      local prefilter = copy[i].prefilter
      if prefilter == nil or prefilter(value) then list[#list + 1] = i end
    end
    return list
  end
  -- The first alternative that accepts the coerced value wins; when none does, the value is left as it is and
  -- the validator reports the union. A single candidate is taken without a second validation of its subtree (the
  -- validator of the whole call checks the result once).
  local coercer = function(value, at, out)
    local memoised = type(value) == "table" and (fast or attempts > 0)
    if memoised then
      local known = recall("converted", validators, value)
      if known ~= nil then return known end
    end
    local list = candidates(value)
    for _, i in ipairs(list) do
      if not spend(at, out) then return value end
      local scratch = {}
      attempts = attempts + 1
      local converted = copy[i].coercer(value, at, scratch)
      attempts = attempts - 1
      if budget_violation ~= nil then return value end
      if #scratch == 0 and (#list == 1 or accepts(validators[i], converted, at)) then
        if memoised then remember("converted", validators, value, converted) end
        return converted
      end
    end
    if memoised and budget_violation == nil then remember("converted", validators, value, value) end
    return value
  end
  -- The value has been validated by the validator of the call: with one candidate there is nothing to decide.
  local builder = function(value)
    local list = candidates(value)
    if #list == 1 then return copy[list[1]].builder(value) end
    for _, i in ipairs(list) do
      if accepts(validators[i], value, 0) then return copy[i].builder(value) end
    end
    return value
  end
  -- The alternative that accepts the value represents it. A built instance can hold what its alternative does not
  -- accept as it is (an enumeration member, where the schema wants the name): when no alternative accepts the value,
  -- each is tried on the plain form it gives, and that form must be accepted. Both verdicts are memoised per node.
  local representers, second_pass = {}, {}
  for i = 1, count do representers[i] = copy[i].representer end
  local representer = represented(function(value, at)
    local memoised = type(value) == "table" and (fast or attempts > 0)
    if memoised then
      local known = recall("converted", representers, value)
      if known ~= nil then return known end
    end
    local result, found = nil, false
    local list = candidates(value)
    for _, i in ipairs(list) do
      if accepts_apart(validators[i], value, at) then
        result, found = representers[i](value, at), true
        break
      end
    end
    if not found then
      -- Second pass, memoised per alternative and per node like the first (OQ-91): the plain form an alternative gives
      -- for a node, or `REJECTED` when that form is not accepted, is computed once within a call.
      local tried = nil
      if memoised then
        tried = recall("converted", second_pass, value)
        if tried == nil then tried = {}; remember("converted", second_pass, value, tried) end
      end
      attempts = attempts + 1 -- the alternatives below are attempts: a nested union reaches the same nodes again
      for _, i in ipairs(list) do
        local plain = tried and tried[i]
        if plain == nil then
          plain = representers[i](value, at)
          if not accepts_apart(validators[i], plain, at) then plain = REJECTED end
          if tried ~= nil and budget_violation == nil then tried[i] = plain end
        end
        if plain ~= REJECTED then result, found = plain, true break end
      end
      attempts = attempts - 1
    end
    if not found then stop_representation(path_to(at), "union", "the value matches none of the alternatives") end
    if memoised then remember("converted", representers, value, result) end
    return result
  end)
  return Schema("union", { members = copy, coercer = coercer, builder = builder, representer = representer, validator = function(value, at, out)
    local memoised = fast and type(value) == "table" -- only an alternative attempt (fail-fast) can reach a node again
    local known = nil
    if memoised then known = recall("verdicts", validators, value) end
    if known == true then return end
    -- A rejected node is not tried again; only the report below is still to be made.
    local last = count
    if known == false then last = 0 end
    for i = 1, last do
      if not spend(at, out) then return end
      if fast then
        local found = {}
        validators[i](value, at, found)
        if found[1] == nil and budget_violation == nil then
          if memoised then remember("verdicts", validators, value, true) end
          return
        end
      elseif accepts(validators[i], value, at) then
        if memoised then remember("verdicts", validators, value, true) end
        return
      end
      if budget_violation ~= nil then
        out[#out + 1] = budget_violation
        return
      end
    end
    if memoised then remember("verdicts", validators, value, false) end
    local failures = {}
    if not fast and detailing == 0 then
      -- Every alternative failed: only now are their violations computed, once, in full mode.
      detailing = 1
      for i = 1, count do
        local found = {}
        validators[i](value, at, found)
        if budget_violation ~= nil then break end
        failures[i] = to_violations(found)
      end
      detailing = 0
      if budget_violation ~= nil then
        out[#out + 1] = budget_violation
        return
      end
    end
    out[#out + 1] = { where(at), "union", "the value matches none of the alternatives", { alternatives = failures } }
  end })
end

--- Gives a property a default: the property may be absent, and `coerce` (texts) and `build` (JSON content, except
--- PATCH) then supply `value` (a deep copy).
--- Validation never supplies it (it validates the value it is given), and JSON Schema emits it as the `default`
--- annotation (section 9.2), which does not change what is valid. The default must conform to `inner` (OQ-88).
---@param inner hecate.schema.Schema
---@param value any  a JSON value that conforms to `inner`
---@return hecate.schema.Schema
function M.default(inner, value)
  require_schema("default", inner)
  if inner.kind == "optional" or inner.kind == "default" then refuse("default: the property is already optional") end
  if value == nil then refuse("default: a default value is required (use json.null for null)") end
  local raw = {}
  inner.validator(value, 0, raw)
  if #raw > 0 then
    refuse(("default: the value does not conform to the schema; first violation at %s: %s")
      :format(raw[1][1] == "" and '""' or raw[1][1], raw[1][3]), { code = raw[1][2], path = raw[1][1] })
  end
  -- Kept in a closure: nothing a caller holds reaches the stored table, only copies do (s1).
  local stored = copy_value(value)
  local coerce_inner = inner.coercer
  return Schema("default", { copy_default = function() return copy_value(stored) end, item = inner, validator = inner.validator, builder = inner.builder,
    representer = inner.representer, -- an absent value stays absent: a response never takes the default
    coercer = function(v, at, out)
      if v == nil then
        if without_defaults then return nil end
        return copy_value(stored) -- explicit: the stored default may be `false`
      end
      return coerce_inner(v, at, out)
    end })
end

--- The set of the attributes of `value` that came from a default in the `build` with `coerce` in progress, or nil
--- (OQ-93). Read by the build of a class-bound instance (`schema.of`), which cannot reach `defaulted` itself.
---@param value table
---@return table<string, true>?
function M.defaulted_for(value)
  return defaulted ~= nil and defaulted[value] or nil
end

--- Validates `value` and collects every violation, in the order of the declaration (properties by name).
---@param value any
---@return boolean ok  true when the value conforms
---@return hecate.schema.Violation[]? violations  present only when `ok` is false
function Schema:validate(value)
  if value == nil and self.kind == "optional" then return true end -- absent is what `optional` allows
  local raw = {}
  reset_work()
  self.validator(value, 0, raw)
  if #raw == 0 and budget_violation == nil then return true end
  return false, to_violations(raw)
end

--- Converts a value read from text (path, query or header fields: strings, lists of strings for repeated keys,
--- tables of them) to the type of the schema, then validates the result. Texts convert as follows: `integer` and
--- `number` read the JSON number grammar, `boolean` reads `true` or `false`, `array` splits a text on its
--- `delimiter` option (default ",") or takes a list, `object` converts its declared properties, `union` takes the
--- first alternative that accepts the converted value. Values that are not texts are validated as they are, and
--- the input is never modified. A text that cannot be converted yields a `coercion` violation.
---@param value any
---@return boolean ok  true when the value converted and conforms
---@return any result  the converted value when `ok`, else a list of `hecate.schema.Violation`
---@overload fun(self: hecate.schema.Schema, value: any): true, any
---@overload fun(self: hecate.schema.Schema, value: any): false, hecate.schema.Violation[]
function Schema:coerce(value)
  if value == nil and self.kind == "optional" then return true, nil end -- absent is what `optional` allows
  local raw = {}
  reset_work()
  local converted = self.coercer(value, 0, raw)
  depth = 0
  if #raw == 0 and budget_violation == nil then self.validator(converted, 0, raw) end
  if #raw == 0 and budget_violation == nil then return true, converted end
  return false, to_violations(raw)
end

--- The members of the schema, as a new list: the alternatives of a `union` (in declaration order), the variant names of
--- a `tagged_union` (sorted), the constants of an `enumeration` (the names of a `core.enumeration`); empty for any other
--- kind.
---@return any[] members
function Schema:members()
  return self._members()
end

local METHODS = { POST = false, PUT = false, PATCH = true }

--- Validates decoded content (no text conversion) and builds the value it describes: every class-bound part (see
--- `schema.of`) becomes an instance of its class, whose attributes are the properties of its schema. An absent
--- attribute is nil, an explicit `null` is nil too and `schema.sent` tells them apart. An absent property declared
--- with `default` takes a fresh deep copy of its default (the content is never modified, and `schema.sent` stays false
--- for it), for every method except PATCH, where an absent attribute means unchanged and no default applies; an
--- explicit `null` never takes the default (OQ-88). With `options.coerce = true` the content is read from text (path,
--- query and header fields) first: it is converted with the rules of `coerce` (a failed conversion gives the same
--- `coercion` violations), defaults apply once, in that conversion, and `schema.sent` records only the attributes that
--- were provided (OQ-93). `options.method` is the HTTP
--- method the content arrived with (OQ-50): `"POST"` and `"PUT"` (the default) are strict; `"PATCH"` lets the
--- required properties of the top-level object be absent (unchanged), while `null` still fails unless nullable. A
--- top-level `optional` schema accepts an absent value (nil) and yields nil, in `validate` and `coerce` too.
---@param value any  decoded content
---@param options? hecate.schema.BuildOptions
---@return boolean ok  true when the content conforms
---@return any result  the built value when `ok`, else a list of `hecate.schema.Violation`
---@overload fun(self: hecate.schema.Schema, value: any, options?: hecate.schema.BuildOptions): true, any
---@overload fun(self: hecate.schema.Schema, value: any, options?: hecate.schema.BuildOptions): false, hecate.schema.Violation[]
function Schema:build(value, options)
  local relax, coerce = false, false
  if options ~= nil then
    local o = read_options("build", options, { method = "string", coerce = "boolean" })
    coerce = o.coerce == true
    if o.method ~= nil then
      relax = METHODS[o.method]
      if relax == nil then refuse("build: method must be POST, PUT or PATCH, got " .. o.method, { option = "method" }) end
    end
  end
  if value == nil and self.kind == "optional" then return true, nil end -- absent is what `optional` allows
  local raw = {}
  reset_work()
  without_defaults = relax == true
  if coerce then
    -- Texts first, with the rules of `coerce` (defaults of the object coercers included, except for a PATCH); the
    -- build below then finds every default already applied and applies none a second time.
    defaulted = {}
    value = self.coercer(value, 0, raw)
    depth = 0
    if #raw > 0 or budget_violation ~= nil then
      defaulted = nil
      return false, to_violations(raw)
    end
  end
  -- A top-level `default` replaces an absent value, as in `coerce`, except for a PATCH.
  if value == nil and not relax and self.kind == "default" then value = self.copy_default() end
  ;(relax and self.relaxed_validator or self.validator)(value, 0, raw)
  if #raw == 0 and budget_violation == nil then
    local built = self.builder(value)
    defaulted = nil
    if budget_violation ~= nil then return false, to_violations(raw) end
    return true, built
  end
  defaulted = nil
  return false, to_violations(raw)
end

--- Converts a value to the plain, JSON-ready form of a response, its representation: the value is passed through the
--- schema and the result is then encoded with `hecate.json.encode`, which stays unaware of classes. A class-bound part
--- (an instance of a class or of a `value_class`) becomes a plain table of the attributes its schema declares, and
--- only those (an undeclared attribute never appears); an enumeration member of a `core.enumeration` becomes its
--- name; nested parts, arrays, maps, unions (the alternative that accepts the value) and tagged unions (the tag
--- selects the variant) convert recursively. An absent (nil) attribute is omitted, `json.null` stays null, a
--- `default` is not applied, and the value is not validated (a response that does not conform is a bug of the server;
--- `validate` checks it where wanted), except where a union must choose an alternative. The result is made of fresh
--- tables (the input is not modified and never shared), arrays and objects carry the `json.array` and `json.object`
--- markers so that an empty one encodes as `[]` or `{}`. The nesting guard of validation (`json.DEFAULT_MAX_DEPTH`)
--- and its work budget apply: a cycle in the object graph, a table too deep or too costly raises
--- `hecate.core.ValidationError` whose first violation (`context.violations`) has the code (`depth_limit`,
--- `complexity_limit`, `union`, `tagged_union` or `enum`) and the JSON Pointer where it stopped.
---@param value any
---@return any plain
function Schema:represent(value)
  reset_work()
  return self.representer(value, 0)
end

--- Returns `value` when it conforms; raises `hecate.core.ValidationError` otherwise, with every violation in
--- `context.violations`. The message names the count and the code of the first violation, never its JSON Pointer,
--- which can hold a key supplied by a user and would reach the logs (OQ-120 (2)).
---@generic T
---@param value T
---@return T
function Schema:check(value)
  local ok, violations = self:validate(value)
  if not ok then
    ---@cast violations hecate.schema.Violation[]
    error(core.ValidationError(("%d violation(s), first violation code '%s'; the JSON Pointer is in context.violations")
      :format(#violations, violations[1].code),
      { context = { violations = violations } }))
  end
  return value
end

M.where = where
M.type_violation = type_violation
M.path_to = path_to
M.stop_representation = stop_representation
M.represented = represented
M.attributes_of = attributes_of
M.copy_plain = copy_plain
M.presence_sets = presence_sets
return M
