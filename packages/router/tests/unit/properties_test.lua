---@diagnostic disable: need-check-nil, param-type-mismatch, missing-fields  -- the tests build tables the annotations do not describe
-- Deterministic property tests (seeded generators, the same sequence on every platform): generated route tables are
-- matched against a brute-force oracle, and the cost of matching a static path is shown not to depend on the table.
local test = require("harness.test")
local router = require("hecate.router")
local T = test.Case("RouterPropertiesTest")

local function generator(seed)
  local state = seed
  return function(n)
    state = (state * 6364136223846793005 + 1442695040888963407) & 0x7fffffffffffffff
    return (state >> 33) % n
  end
end

local LITERALS <const> = { "a", "b", "c", "users", "x1" }
local METHODS <const> = { "GET", "POST", "PUT", "DELETE" }

--- A random template as a list of kinds, and its text; parameter names are unique per template.
local function random_template(rand)
  local kinds, parts = {}, {}
  local count = 1 + rand(4)
  for i = 1, count do
    local roll = rand(10)
    if roll < 5 then
      kinds[i] = LITERALS[rand(#LITERALS) + 1]
      parts[i] = kinds[i]
    elseif roll < 9 or i < count then
      kinds[i] = "{}"
      parts[i] = "{p" .. i .. "}"
    else
      kinds[i] = "{...}"
      parts[i] = "{p" .. i .. "...}"
    end
  end
  return kinds, "/" .. table.concat(parts, "/")
end

--- Rank of a segment kind in the precedence order: static, parameter, wildcard.
local function rank(kind) return kind == "{...}" and 3 or kind == "{}" and 2 or 1 end

--- Whether a template (kinds) matches the segments of a request path.
local function template_matches(kinds, segments)
  for i, kind in ipairs(kinds) do
    if kind == "{...}" then return #segments >= i end
    if segments[i] == nil then return false end
    if kind ~= "{}" and kind ~= segments[i] then return false end
  end
  return #kinds == #segments
end

--- True when template `a` has precedence over `b`: the first difference decides, static before parameter before wildcard.
local function precedes(a, b)
  for i = 1, math.max(#a, #b) do
    if a[i] ~= b[i] then
      if a[i] == nil then return true end
      if b[i] == nil then return false end
      local ra, rb = rank(a[i]), rank(b[i])
      if ra ~= rb then return ra < rb end
      return a[i] < b[i]
    end
  end
  return false
end

local function random_path(rand)
  local segments = {}
  for i = 1, 1 + rand(5) do segments[i] = LITERALS[rand(#LITERALS) + 1] end
  return segments
end

function T:test_the_router_agrees_with_a_brute_force_oracle_on_generated_tables()
  for seed = 1, 60 do
    local rand = generator(seed)
    local list, entries, taken = {}, {}, {}
    for _ = 1, 3 + rand(12) do
      local kinds, text = random_template(rand)
      local method = METHODS[rand(#METHODS) + 1]
      local shape = method .. " " .. table.concat(kinds, "/")
      if not taken[shape] then
        taken[shape] = true
        local route = { method = method, path = text, name = "r" .. (#list + 1) }
        list[#list + 1] = route
        entries[#entries + 1] = { route = route, kinds = kinds }
      end
    end
    local r = router.Router(list, { automatic_head = false, automatic_options = false })
    for _ = 1, 40 do
      local segments = random_path(rand)
      local method = METHODS[rand(#METHODS) + 1]
      local best, any = nil, false
      for _, entry in ipairs(entries) do
        if template_matches(entry.kinds, segments) then
          any = true
          if entry.route.method == method and (best == nil or precedes(entry.kinds, best.kinds)) then best = entry end
        end
      end
      local m = r:match(method, "/" .. table.concat(segments, "/"))
      local label = ("seed %d %s /%s"):format(seed, method, table.concat(segments, "/"))
      if best then
        self:assert_equal(200, m.status, label)
        self:assert_true(m.route == best.route, label .. ": expected " .. best.route.path .. ", got " .. tostring(m.route and m.route.path))
      elseif any then
        self:assert_equal(405, m.status, label)
      else
        self:assert_equal(404, m.status, label)
      end
    end
  end
end

function T:test_every_declared_route_is_found_by_its_own_reverse_url()
  for seed = 1, 30 do
    local rand = generator(1000 + seed)
    local list, taken = {}, {}
    for _ = 1, 5 + rand(15) do
      local kinds, text = random_template(rand)
      local shape = table.concat(kinds, "/")
      if not taken[shape] then
        taken[shape] = true
        list[#list + 1] = { method = "GET", path = text, name = "r" .. (#list + 1) }
      end
    end
    local r = router.Router(list)
    for _, route in ipairs(list) do
      local parameters = {}
      for name, wildcard in route.path:gmatch("{([%w]+)(%.?%.?%.?)}") do
        parameters[name] = wildcard == "" and ("v " .. name) or "w/" .. name
      end
      local url = r:url_for(route.name, parameters)
      local m = r:match("GET", url)
      self:assert_equal(200, m.status, url)
      -- A more specific route may take precedence over this one; the parameters it binds then differ.
      if m.route == route then
        for name, value in pairs(parameters) do self:assert_equal(value, m.parameters[name], url) end
      end
    end
  end
end

--- The number of VM instructions executed by `fn`.
local function instructions(fn)
  local count = 0
  debug.sethook(function() count = count + 1 end, "", 1)
  fn()
  debug.sethook()
  return count
end

function T:test_the_cost_of_matching_a_static_path_does_not_depend_on_the_number_of_routes()
  local function table_of(size)
    local list = {}
    for i = 1, size do
      list[#list + 1] = { method = "GET", path = ("/api/v1/resource%d/{id}/items/%d"):format(i, i) }
      list[#list + 1] = { method = "GET", path = ("/static%d/{rest...}"):format(i) }
    end
    list[#list + 1] = { method = "GET", path = "/api/v1/target/{id}/items/last", name = "target" }
    return router.Router(list)
  end
  local small, large = table_of(5), table_of(5000)
  local function cost(r) return instructions(function() r:match("GET", "/api/v1/target/42/items/last") end) end
  cost(small); cost(large) -- warm up
  self:assert_equal(cost(small), cost(large), "the same instructions for 11 and 10001 routes")
  local function miss(r) return instructions(function() r:match("GET", "/api/v1/nothing/42/items/last") end) end
  self:assert_equal(miss(small), miss(large))
end

function T:test_the_cost_grows_with_the_path_length()
  local r = router.Router({ { method = "GET", path = "/{rest...}" } })
  local function cost(path) return instructions(function() r:match("GET", path) end) end
  cost("/a")
  self:assert_true(cost("/a/b/c/d/e/f/g/h") > cost("/a/b"))
end

return T
