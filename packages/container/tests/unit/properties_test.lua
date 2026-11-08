---@diagnostic disable: need-check-nil, param-type-mismatch, missing-fields, undefined-field  -- the tests build tables the annotations do not describe
-- Deterministic property test (seeded generator, the same sequence on every platform): for random graphs, either
-- `validate` raises one `GraphError`, or every resolution succeeds without a structural error (container.md,
-- "Boot validation", the invariant), and the verdict agrees with an independent oracle.
local test = require("harness.test")
local core = require("hecate.core")
local container = require("hecate.container")
local T = test.Case("ContainerPropertiesTest")

local function generator(seed)
  local state = seed
  return function(n)
    state = (state * 6364136223846793005 + 1442695040888963407) & 0x7fffffffffffffff
    return (state >> 33) % n
  end
end

local LIFETIMES <const> = { "singleton", "scoped", "transient" }

--- A random graph: `size` bindings, each requiring up to three keys among `size + 1` names (the last is never bound).
local function random_graph(rand)
  local size = 2 + rand(7)
  local nodes = {}
  for i = 1, size do
    local requires = {}
    for j = 1, rand(4) do requires[j] = "k" .. (1 + rand(size + (rand(6) == 0 and 1 or 0))) end
    nodes[i] = { key = "k" .. i, lifetime = LIFETIMES[1 + rand(3)], requires = requires }
  end
  return nodes
end

--- Oracle: is the graph valid? Missing key, cycle (by reachability to itself) or captive dependency.
local function oracle(nodes)
  local by_key = {}
  for _, node in ipairs(nodes) do by_key[node.key] = node end
  for _, node in ipairs(nodes) do
    for _, dependency in ipairs(node.requires) do if not by_key[dependency] then return false end end
  end
  local function reaches(from, goal, seen)
    for _, dependency in ipairs(by_key[from].requires) do
      if dependency == goal then return true end
      if not seen[dependency] then
        seen[dependency] = true
        if reaches(dependency, goal, seen) then return true end
      end
    end
    return false
  end
  for _, node in ipairs(nodes) do if reaches(node.key, node.key, {}) then return false end end
  local function captive(node, seen)
    for _, dependency in ipairs(node.requires) do
      local target = by_key[dependency]
      if target.lifetime == "scoped" then return true end
      if target.lifetime == "transient" and not seen[dependency] then
        seen[dependency] = true
        if captive(target, seen) then return true end
      end
    end
    return false
  end
  for _, node in ipairs(nodes) do
    if node.lifetime == "singleton" and captive(node, {}) then return false end
  end
  return true
end

local function build(nodes)
  local c = container.Container()
  for _, node in ipairs(nodes) do
    c:bind(node.key, function(...) return { key = node.key, dependencies = { ... } } end,
      { lifetime = node.lifetime, requires = node.requires })
  end
  return c
end

function T:test_validate_agrees_with_the_oracle_and_a_validated_graph_never_fails_structurally()
  local rand = generator(20261108)
  local valid, invalid = 0, 0
  for _ = 1, 400 do
    local nodes = random_graph(rand)
    local c = build(nodes)
    local ok, err = pcall(function() c:validate() end)
    self:assert_equal(oracle(nodes), ok, "verdict differs from the oracle")
    if ok then
      valid = valid + 1
      local scope = c:open_scope()
      for _, node in ipairs(nodes) do
        local service = scope:resolve(node.key)
        self:assert_equal(node.key, service.key)
        if node.lifetime ~= "scoped" then
          local reachable, root_err = pcall(function() return c:resolve(node.key) end)
          if not reachable then
            self:assert_true(core.is_instance_of(root_err, container.LifetimeError),
              "the only structural error left is the documented root call: " .. tostring(root_err))
          end
        end
      end
      scope:close()
    else
      invalid = invalid + 1
      self:assert_true(core.is_instance_of(err, container.GraphError), tostring(err))
      self:assert_true(#err.context.problems >= 1)
    end
  end
  self:assert_true(valid > 20 and invalid > 20, ("the generator covers both verdicts (%d, %d)"):format(valid, invalid))
end

return T
