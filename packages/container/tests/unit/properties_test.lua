---@diagnostic disable: need-check-nil, param-type-mismatch, missing-fields, undefined-field  -- the tests build tables the annotations do not describe
-- Deterministic property test (seeded generator, the same sequence on every platform): for random graphs, either
-- `validate` raises one `GraphError`, or every resolution succeeds without a structural error (container.md,
-- "Boot validation", the invariant), and the verdict agrees with an independent oracle. Root resolution agrees with
-- an oracle of root-resolvability, and every closable product is closed once, after the products that received it.
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

--- Oracle of root resolution for a valid graph: `Container:resolve` succeeds for a singleton, and for a transient that
--- needs no scoped service and creates no closable transient that no singleton owns; everything else is a
--- `LifetimeError` (container.md, "Resolution entry points" and "Root resolution").
local function root_resolvable(nodes)
  local by_key = {}
  for _, node in ipairs(nodes) do by_key[node.key] = node end
  local function needs_scope(node)
    if node.lifetime == "scoped" then return true end
    if node.lifetime == "singleton" then return false end
    for _, dependency in ipairs(node.requires) do if needs_scope(by_key[dependency]) then return true end end
    return false
  end
  local function unowned(node)
    if node.closable then return true end
    for _, dependency in ipairs(node.requires) do
      local target = by_key[dependency]
      if target.lifetime == "transient" and unowned(target) then return true end
    end
    return false
  end
  return function(node)
    if node.lifetime == "singleton" then return true end
    return node.lifetime == "transient" and not needs_scope(node) and not unowned(node)
  end
end

--- Binds the nodes. A closable node builds products with `__close`; a node is defined by a class or by a factory;
--- some are first bound to something else and then overridden. `log` records creations and closes.
local function build(nodes, rand, log)
  local c = container.Container()
  local function product(node, target, ...)
    log.count = log.count + 1
    target.key, target.id, target.dependencies = node.key, log.count, { ... }
    log.created[#log.created + 1] = target
    return target
  end
  local function on_close(target)
    log.closes[target.id] = (log.closes[target.id] or 0) + 1
    log.order[#log.order + 1] = target
  end
  local closable_meta = { __close = on_close }
  for _, node in ipairs(nodes) do
    local definition
    if node.class then
      local class = core.class("Node" .. node.key)
      function class:init(...) product(node, self, ...) end
      if node.closable then class.__close = on_close end
      definition = core.finalise(class)
    else
      definition = function(...)
        return product(node, node.closable and setmetatable({}, closable_meta) or {}, ...)
      end
    end
    if node.overridden then
      c:bind(node.key, function() return {} end, { lifetime = LIFETIMES[1 + rand(3)] })
      c:override(node.key, definition, { lifetime = node.lifetime, requires = node.requires })
    else
      c:bind(node.key, definition, { lifetime = node.lifetime, requires = node.requires })
    end
  end
  return c
end

function T:test_validate_agrees_with_the_oracle_and_a_validated_graph_never_fails_structurally()
  local rand = generator(20261108)
  local flags = generator(20261113) -- a second sequence, so that the graphs are those of the first one
  local valid, invalid, refused, closed = 0, 0, 0, 0
  for _ = 1, 800 do
    local nodes = random_graph(rand)
    for _, node in ipairs(nodes) do
      node.closable, node.class, node.overridden = flags(3) == 0, flags(2) == 0, flags(5) == 0
    end
    local log = { count = 0, created = {}, closes = {}, order = {} }
    local c = build(nodes, flags, log)
    local ok, err = pcall(function() c:validate() end)
    self:assert_equal(oracle(nodes), ok, "verdict differs from the oracle")
    if ok then
      valid = valid + 1
      local from_root = root_resolvable(nodes)
      local scope = c:open_scope()
      for _, node in ipairs(nodes) do
        local service = scope:resolve(node.key)
        self:assert_equal(node.key, service.key)
        local reachable, root_err = pcall(function() return c:resolve(node.key) end)
        self:assert_equal(from_root(node), reachable,
          ("root resolution of %s (%s): %s"):format(node.key, node.lifetime, tostring(root_err)))
        if not reachable then
          refused = refused + 1
          self:assert_true(core.is_instance_of(root_err, container.LifetimeError),
            "the only structural error left is the documented root call: " .. tostring(root_err))
        end
      end
      local before = {}
      for id in pairs(log.closes) do before[id] = true end
      scope:close()
      for _, made in ipairs(log.created) do
        local node
        for _, candidate in ipairs(nodes) do if candidate.key == made.key then node = candidate end end
        if node.lifetime == "singleton" then
          self:assert_equal(nil, not before[made.id] and log.closes[made.id] or nil, "a scope never closes a singleton")
        elseif node.lifetime == "scoped" and node.closable then
          self:assert_equal(1, log.closes[made.id], "the scope closes its scoped services")
        end
      end
      c:close()
      -- Every closable product is closed exactly once, and after every product that received it (reverse order of
      -- creation within an owner, service scopes before the container).
      local position = {}
      for i, made in ipairs(log.order) do position[made] = i end
      for _, made in ipairs(log.created) do
        if getmetatable(made) and getmetatable(made).__close then
          closed = closed + 1
          self:assert_equal(1, log.closes[made.id], "closed exactly once: " .. made.key)
          for _, dependency in ipairs(made.dependencies) do
            if position[dependency] then
              self:assert_true(position[dependency] > position[made],
                ("%s closed before %s, which received it"):format(dependency.key, made.key))
            end
          end
        else
          self:assert_equal(nil, log.closes[made.id])
        end
      end
    else
      invalid = invalid + 1
      self:assert_true(core.is_instance_of(err, container.GraphError), tostring(err))
      self:assert_true(#err.context.problems >= 1)
    end
  end
  self:assert_true(valid > 40 and invalid > 40, ("the generator covers both verdicts (%d, %d)"):format(valid, invalid))
  self:assert_true(refused > 20 and closed > 100, ("root refusals and closes are covered (%d, %d)"):format(refused, closed))
end

return T
