-- The container and its service scopes. Construction is constructor injection of explicitly declared dependencies
-- (Fowler 2004, "Forms of Dependency Injection"); the graph is composed in one place and validated before use
-- (Seemann 2011, section 3.2 "Composition Root"). Nothing here suspends, so no instance is ever created twice and no
-- lock is needed (container.md, "Construction"); a constructor that suspends anyway (OQ-107) is detected and refused.
global <const> require, type, pairs, ipairs, pcall, error, table, getmetatable, tostring, coroutine

local core = require("hecate.core")
local errors = require("hecate.container.errors")
local graph = require("hecate.container.graph")
local Lifetime = require("hecate.container.lifetime")

local ContainerError = errors.ContainerError
local render = graph.render

--- Options of `bind` and `override`.
---@class hecate.container.BindOptions
---@field lifetime? hecate.core.EnumerationValue|"singleton"|"scoped"|"transient"  required
---@field requires? (string|table)[]  keys of the services passed to the constructor or factory, in order

local OPTION_NAMES <const> = { "lifetime", "requires" }

local function argument_error(method, message)
  error(core.ArgumentError("container." .. method .. ": " .. message), 3)
end

local function is_key(key)
  return (type(key) == "string" and key ~= "") or core.is_interface(key)
end

local function check_key(method, key, what)
  if not is_key(key) then argument_error(method, what .. " must be a non-empty string or an interface") end
end

local function check_definition(method, definition)
  if core.is_class(definition) then
    if not core.is_finalised(definition) then argument_error(method, "the class definition is not finalised") end
  elseif type(definition) ~= "function" then
    argument_error(method, "definition must be a finalised class or a function")
  end
end

--- Reads and checks `options`; `fallback` gives the values for the keys that are absent.
local function read_options(method, options, fallback)
  if options ~= nil and type(options) ~= "table" then argument_error(method, "options must be a table") end
  options = options or {}
  for key in pairs(options) do
    local known = false
    for _, name in ipairs(OPTION_NAMES) do if name == key then known = true end end
    if not known then
      argument_error(method, ("unknown option %s (known: %s)"):format(tostring(key), table.concat(OPTION_NAMES, ", ")))
    end
  end
  local lifetime = options.lifetime
  if lifetime == nil then
    if fallback == nil then
      argument_error(method, "option lifetime is required: singleton (one per process), scoped (one per request) or transient (a new one each time)")
    end
    lifetime = fallback.lifetime
  elseif type(lifetime) == "string" then
    lifetime = Lifetime:find(lifetime)
    if lifetime == nil then argument_error(method, "option lifetime must be singleton, scoped or transient") end
  elseif not Lifetime:contains(lifetime) then
    argument_error(method, "option lifetime must be singleton, scoped or transient")
  end
  local requires = options.requires
  if requires == nil then
    requires = fallback and fallback.requires or {}
  else
    if type(requires) ~= "table" then argument_error(method, "option requires must be a list of keys") end
    local count = 0
    for _ in pairs(requires) do count = count + 1 end
    if count ~= #requires then argument_error(method, "option requires must be a list of keys") end
    for _, dependency in ipairs(requires) do check_key(method, dependency, "each key of option requires") end
  end
  local copy = {}
  for i, dependency in ipairs(requires) do copy[i] = dependency end
  return lifetime, copy
end

--- Closes `owned` in reverse order of creation; every close is attempted, the first error is raised afterwards with
--- the others in `context.suppressed` (container.md, "Disposal").
local function close_all(owned)
  local failures = {}
  for i = #owned, 1, -1 do
    local service = owned[i]
    owned[i] = nil
    local ok, failure = pcall(getmetatable(service).__close, service, nil)
    if not ok then failures[#failures + 1] = failure end
  end
  if #failures == 0 then return end
  local first = table.remove(failures, 1)
  if not (type(first) == "table" and core.is_instance_of(first, core.Error)) then
    first = ContainerError("container: closing a service failed", { cause = first })
  end
  if #failures > 0 then first.context.suppressed = failures end
  error(first, 0)
end

--- Attaches `failure` (a close error) to `context.suppressed` of `err` when `err` is a framework error.
local function suppress(err, failure)
  if type(err) == "table" and core.is_instance_of(err, core.Error) then
    local list = err.context.suppressed or {}
    list[#list + 1] = failure
    err.context.suppressed = list
  end
end

local function rendered_path(path)
  local rendered = {}
  for i, entry in ipairs(path) do rendered[i] = render(entry) end
  return rendered
end

--- Tracks `instance` in `holder` (a service scope or the container) unless it already does: an owner closes an
--- instance once, however many times it was returned (container.md, "Disposal"). Returns whether it was added.
local function track(holder, instance)
  if holder._tracked[instance] then return false end
  holder._tracked[instance] = true
  holder._owned[#holder._owned + 1] = instance
  return true
end

--- Stops tracking `instance` in `holder`.
local function untrack(holder, instance)
  holder._tracked[instance] = nil
  local owned = holder._owned
  for i = #owned, 1, -1 do
    if owned[i] == instance then
      table.remove(owned, i)
      return
    end
  end
end

local function closeable(service)
  if type(service) ~= "table" and type(service) ~= "userdata" then return false end
  local metatable = getmetatable(service)
  return type(metatable) == "table" and metatable.__close ~= nil
end

--- Whether the instances of a class definition define `__close`; the class is the metatable of its instances.
local function class_closeable(definition)
  return core.is_class(definition) and definition.__close ~= nil
end

--- Refuses a closable transient that no service scope and no singleton owns (container.md, "Disposal").
local function refuse_unowned(path)
  local rendered = rendered_path(path)
  error(errors.LifetimeError(
    ("container: %q is a transient with __close and no service scope owns it: resolve it through a ServiceScope made by container:open_scope()")
      :format(rendered[#rendered]),
    { context = { key = rendered[1], dependency = rendered[#rendered], path = rendered } }), 0)
end

--- A container: bindings, lifetimes, validation at boot and resolution by constructor injection. It is composed in one
--- place (the composition root), validated with `validate`, then used; there is no global container and no way to
--- reach one from a service.
---@class hecate.container.Container
---@overload fun(): hecate.container.Container
local Container = core.class("Container")

--- A scope of lifetime of scoped services, made by `Container:open_scope`: one per request, closed by its owner.
--- Not constructible from outside: `ServiceScope(x)` raises `hecate.core.ArgumentError` unless `x` is a `Container`;
--- use `Container:open_scope()`.
---@class hecate.container.ServiceScope
---@overload fun(container: hecate.container.Container): hecate.container.ServiceScope
local ServiceScope = core.class("ServiceScope")

--- Make an empty container.
function Container:init()
  self._bindings = {}
  self._order = {}
  self._singletons = {}
  self._owned = {}
  self._tracked = {} -- the instances in `_owned`, as a set
  self._validated = false
  self._warnings = {}
  self._closed = false
end

local function check_open(container, method)
  if container._closed then error(ContainerError("container: " .. method .. " on a closed container"), 3) end
end

local function check_unfrozen(container, method)
  check_open(container, method)
  if container._validated then
    error(ContainerError("container: " .. method .. " after validate: the container is frozen"), 3)
  end
end

local function check_validated(container, method)
  check_open(container, method)
  if not container._validated then
    error(ContainerError("container: " .. method .. " before validate: validate the container at boot"), 3)
  end
end

--- Binds `key` to a way of building a service. `definition` is a finalised class or a factory function, called with
--- the resolved services of `options.requires`, in order; it must not suspend. When `key` is an interface and
--- `definition` a class, `validate` checks that the class implements it; a factory product is checked at its first
--- construction.
---
--- Raises `hecate.container.DuplicateBindingError` if `key` is bound, `hecate.container.ContainerError` after
--- `validate` or `close`, and `hecate.core.ArgumentError` for a wrong argument.
---@param key string|table  a non-empty name or an interface
---@param definition table|function  a finalised class or a factory
---@param options? hecate.container.BindOptions
---@return hecate.container.Container self
function Container:bind(key, definition, options)
  check_key("bind", key, "key")
  check_definition("bind", definition)
  local lifetime, requires = read_options("bind", options, nil)
  check_unfrozen(self, "bind")
  if self._bindings[key] ~= nil then
    error(errors.DuplicateBindingError(("container: %q is already bound"):format(render(key)),
      { context = { key = render(key) } }), 2)
  end
  self._bindings[key] = { key = key, definition = definition, lifetime = lifetime, requires = requires }
  self._order[#self._order + 1] = key
  return self
end

--- Tells whether `key` has a binding, without constructing anything; it does not need `validate`. The kernel uses it
--- at boot to check the keys it will resolve (container.md, "Keys").
---
--- Raises `hecate.container.ContainerError` after `close`, and `hecate.core.ArgumentError` if `key` is not a
--- non-empty string or an interface.
---@param key string|table  a non-empty name or an interface
---@return boolean bound
function Container:has(key)
  check_key("has", key, "key")
  check_open(self, "has")
  return self._bindings[key] ~= nil
end

--- Replaces the binding of `key`, for tests. When `options` is omitted the lifetime and `requires` of the replaced
--- binding are kept; when given, it replaces both (the lifetime is required, as for `bind`). The new graph is checked by `validate`.
---
--- Raises `hecate.container.MissingBindingError` if `key` is not bound, `hecate.container.ContainerError` after
--- `validate` or `close`, and `hecate.core.ArgumentError` for a wrong argument.
---@param key string|table
---@param definition table|function
---@param options? hecate.container.BindOptions
---@return hecate.container.Container self
function Container:override(key, definition, options)
  check_key("override", key, "key")
  check_definition("override", definition)
  local previous = self._bindings[key]
  local lifetime, requires
  if options == nil and previous ~= nil then
    lifetime, requires = previous.lifetime, previous.requires
  elseif options ~= nil then
    lifetime, requires = read_options("override", options, nil)
  end
  check_unfrozen(self, "override")
  if previous == nil then
    error(errors.MissingBindingError(("container: cannot override %q, it is not bound"):format(render(key)),
      { context = { key = render(key), path = { render(key) } } }), 2)
  end
  self._bindings[key] = { key = key, definition = definition, lifetime = lifetime, requires = requires }
  return self
end

--- Replaces the binding of `key` by an existing object, as a singleton without dependencies: the usual way to inject
--- a fake. Like `override`, `key` must already be bound. When `key` is an interface, the conformance of `value` is
--- checked here, at the call, because its class is known (a value that is not an instance of a class does not
--- implement the interface, as for a factory product); the binding is unchanged on failure. A name key carries no
--- check. (container.md, "Overrides for tests"; Fowler 2004, "Forms of Dependency Injection".)
---
--- Raises `hecate.container.MissingBindingError` if `key` is not bound, `hecate.container.ContainerError` after
--- `validate` or `close`, `hecate.core.ConformanceError` if `value` does not implement the interface `key`, and
--- `hecate.core.ArgumentError` for a wrong argument.
---@param key string|table
---@param value any  the object; never `nil`
---@return hecate.container.Container self
function Container:override_with_instance(key, value)
  check_key("override_with_instance", key, "key")
  if value == nil then argument_error("override_with_instance", "value must not be nil") end
  check_unfrozen(self, "override_with_instance")
  if self._bindings[key] ~= nil and core.is_interface(key) and not core.implements(value, key) then
    error(core.ConformanceError(("container: the instance for %q does not implement it"):format(render(key)),
      { context = { key = render(key) } }), 2)
  end
  return self:override(key, function() return value end, { lifetime = Lifetime.singleton })
end

--- Checks the whole graph without constructing anything, then freezes the container. Collects every problem:
--- missing bindings, cycles, a singleton that depends on a scoped service (directly or through transients), and a
--- class that does not implement its interface key. It may be called again once it succeeded.
---
--- Raises `hecate.container.GraphError`; `context.problems` lists the individual errors in the order of binding.
--- Returns the container and the warnings: a singleton that directly depends on a transient (`code =
--- "singleton_over_transient"`: the transient is built once and lives as long as the process). Warnings never fail the
--- validation; the caller (the kernel) reports them. Every later call returns the same list.
---@return hecate.container.Container self
---@return hecate.container.Warning[] warnings
function Container:validate()
  check_open(self, "validate")
  if self._validated then return self, self._warnings end
  local problems, warnings = graph.check(self._bindings, self._order)
  if #problems > 0 then
    error(errors.GraphError(("container: the graph has %d problem%s; first: %s"):format(
      #problems, #problems == 1 and "" or "s", problems[1].message), { context = { problems = problems } }), 2)
  end
  graph.annotate(self._bindings, self._order)
  self._validated = true
  self._warnings = warnings
  return self, warnings
end

-- The guard of a construction: its `__close` clears the mark of the binding, also when the computation is closed while
-- suspended in the constructor (`coroutine.close` closes pending to-be-closed variables).
--- Internal: the to-be-closed guard of one construction; not exported.
---@class hecate.container.ConstructionGuard
---@field binding hecate.container.Binding
local ConstructionGuard = core.class("ConstructionGuard")

--- Guards the construction of `binding`.
---@param binding hecate.container.Binding
function ConstructionGuard:init(binding) self.binding = binding end

--- Clears the mark of the construction.
function ConstructionGuard:__close() self.binding.constructing = nil end
core.finalise(ConstructionGuard)

--- Closes a closable product that will not be returned, unless an owner already tracks it.
local function discard(container, scope, product, err)
  if not closeable(product) or container._tracked[product] or (scope ~= nil and scope._tracked[product]) then return end
  local closed, failure = pcall(getmetatable(product).__close, product, nil)
  if not closed then suppress(err, failure) end
end

--- Builds the service of `binding` from its resolved dependencies. `binding.constructing` holds the computation that
--- is constructing it (OQ-107: a constructor never suspends, so another computation never sees the mark set).
local function construct(container, scope, binding, args, count, path)
  local key = binding.key
  binding.constructing = coroutine.running()
  local guard <close> = ConstructionGuard(binding)
  local ok, product = pcall(binding.definition, table.unpack(args, 1, count))
  if not ok then
    if core.is_instance_of(product, core.CancellationError) or core.is_instance_of(product, core.DeadlineExceededError) then
      error(product, 0)
    end
    error(errors.ConstructionError(("container: constructing %q failed"):format(render(key)),
      { cause = product, context = { key = render(key), path = rendered_path(path) } }), 0)
  end
  if product == nil then
    error(errors.ConstructionError(("container: the constructor of %q returned nil"):format(render(key)),
      { context = { key = render(key), path = rendered_path(path) } }), 0)
  end
  if core.is_interface(key) and not core.implements(product, key) then
    local failure = core.ConformanceError(("container: the product of %q does not implement it"):format(render(key)),
      { context = { key = render(key), path = rendered_path(path) } })
    discard(container, scope, product, failure)
    error(failure, 0)
  end
  return product
end

local resolve_key

--- Resolves the dependencies of `binding`, then constructs it.
local function build(container, scope, binding, path, owner, pending, journal)
  local count = #binding.requires
  local args = {}
  for i = 1, count do args[i] = resolve_key(container, scope, binding.requires[i], path, owner, pending, journal) end
  return construct(container, scope, binding, args, count, path)
end

--- Closes and drops the closable transients built for a singleton whose construction failed (`journal`), then raises
--- `failure`; a close error is attached to `failure` as `context.suppressed`.
local function abandon(container, journal, failure)
  for i = #journal, 1, -1 do untrack(container, journal[i]) end
  local closed, close_failure = pcall(close_all, journal)
  if not closed then suppress(failure, close_failure) end
  error(failure, 0)
end

--- `path` is the chain of keys being resolved, from the requested key. `owner` is what tracks the closable transients
--- built on the way: the service scope, the container while a singleton is being built, or `nil` from the root, where
--- `pending` collects what was built in this call (refused at the end, container.md, "Disposal"). `journal` lists the
--- closable transients the container took for the singleton being built, dropped if its construction fails.
function resolve_key(container, scope, key, path, owner, pending, journal)
  local binding = container._bindings[key]
  path[#path + 1] = key
  if binding == nil then
    error(errors.MissingBindingError(("container: %q is not bound"):format(render(key)),
      { context = { key = render(key), path = rendered_path(path) } }), 0)
  end
  local lifetime = binding.lifetime
  local cache = nil
  if lifetime == Lifetime.singleton then
    cache = container._singletons
  elseif lifetime == Lifetime.scoped then
    cache = scope._instances
  end
  if cache ~= nil and cache[key] ~= nil then
    path[#path] = nil
    return cache[key]
  end
  local constructing = binding.constructing
  if constructing ~= nil then
    if constructing == coroutine.running() then
      local rendered = { render(key), render(key) }
      error(errors.CycleError("container: re-entrant resolution of " .. rendered[1], { context = { path = rendered } }), 0)
    end
    error(ContainerError(
      ("container: %q is being constructed by a computation that suspended: constructors and factories must not suspend (OQ-107)")
        :format(render(key)), { context = { key = render(key), path = rendered_path(path) } }), 0)
  end
  if lifetime == Lifetime.transient and owner == nil and class_closeable(binding.definition) then
    refuse_unowned(path)
  end
  local product
  if lifetime == Lifetime.singleton then
    -- A singleton is built without a service scope: nothing request-bound can reach it, and the container owns the
    -- closable transients it needs; they are dropped again if its construction fails.
    local built = {}
    local ok, result = pcall(build, container, nil, binding, path, container, nil, built)
    if not ok then abandon(container, built, result) end
    product = result
  else
    product = build(container, scope, binding, path, owner, pending, journal)
  end
  if cache ~= nil then
    cache[key] = product
    if closeable(product) then track(lifetime == Lifetime.singleton and container or scope, product) end
  elseif closeable(product) and not container._tracked[product] and not (scope ~= nil and scope._tracked[product]) then
    -- A product already tracked (a singleton's or a scoped instance, or one returned before) has an owner already.
    if owner ~= nil then
      track(owner, product)
      if owner == scope then scope._released[product] = true end
      if journal ~= nil and owner == container then journal[#journal + 1] = product end
    else
      pending[#pending + 1] = product
      refuse_unowned(path)
    end
  end
  path[#path] = nil
  return product
end

local function check_key_argument(method, key)
  if not is_key(key) then argument_error(method, "key must be a non-empty string or an interface") end
end

--- Resolves a root-resolvable service: a singleton or a transient whose dependencies are all singletons or
--- transients. The container must have been validated.
---
--- A transient whose instance defines `__close` has no owner here: it is refused, see below.
---
--- Raises `hecate.container.LifetimeError` if the service needs a scoped one (use `ServiceScope:resolve`), or if it
--- would create a closable transient that no singleton owns (resolve it through `ServiceScope:resolve`; a factory
--- product is closed again before the error is raised),
--- `hecate.container.MissingBindingError` for an unbound key, `hecate.container.ConstructionError` if a constructor
--- raised, and `hecate.container.ContainerError` before `validate` or after `close`.
---@param key string|table
---@return any service  never `nil`
function Container:resolve(key)
  check_key_argument("resolve", key)
  check_validated(self, "resolve")
  local binding = self._bindings[key]
  if binding ~= nil and binding.needs_scope then
    local path = {}
    for i, entry in ipairs(binding.scoped_path) do path[i] = render(entry) end
    local dependency = path[#path]
    error(errors.LifetimeError(
      ("container: %q needs the scoped service %q: resolve it from a service scope"):format(path[1], dependency),
      { context = { key = path[1], dependency = dependency, path = path } }), 2)
  end
  -- Nothing owns a closable transient built here: what was built in this call is closed again before the refusal.
  local pending = {}
  local ok, result = pcall(resolve_key, self, nil, key, {}, nil, pending, nil)
  if ok then return result end
  if #pending > 0 then
    local closed, failure = pcall(close_all, pending)
    if not closed then suppress(result, failure) end
  end
  error(result, 0)
end

--- Opens a service scope: the lifetime of scoped services. The container must have been validated. The caller owns
--- the scope and closes it (`<close>` or `:close()`).
---@return hecate.container.ServiceScope scope
function Container:open_scope()
  check_validated(self, "open_scope")
  return ServiceScope(self)
end

--- Closes the container: the singletons that define `__close` are closed in reverse order of creation. Idempotent.
--- Every close is attempted; the first error is raised afterwards, the others are in `context.suppressed`.
function Container:close()
  if self._closed then return end
  self._closed = true
  self._tracked = {}
  close_all(self._owned)
end

--- Supports `local c <close> = container.Container()`.
function Container:__close() self:close() end

---@param container hecate.container.Container
function ServiceScope:init(container)
  if type(container) ~= "table" or not core.is_instance_of(container, Container) then
    error(core.ArgumentError("container.ServiceScope: container must be a Container; open a service scope with container:open_scope()"), 3)
  end
  self._container = container
  self._instances = {}
  self._owned = {}
  self._tracked = {} -- the instances in `_owned`, as a set
  self._released = {} -- the closable transients this scope tracks, which `release` may close early
  self._closed = false
end

--- Resolves any service: scoped instances are cached in this scope, singleton instances in the container.
---
--- Raises `hecate.container.MissingBindingError`, `hecate.container.ConstructionError` or
--- `hecate.container.ContainerError` (this scope or the container is closed).
---@param key string|table
---@return any service  never `nil`
function ServiceScope:resolve(key)
  check_key_argument("resolve", key)
  if self._closed then error(ContainerError("container: resolve on a closed service scope"), 2) end
  check_validated(self._container, "resolve")
  return resolve_key(self._container, self, key, {}, self, nil, nil)
end

--- Closes a closable transient now, instead of at the close of this scope, and stops tracking it. A scope that owns a
--- transient closes it: do not close it yourself. A close error propagates as it is.
---
--- Raises `hecate.core.ArgumentError` if `instance` is neither a table nor a userdata, and `hecate.container.ContainerError` if this
--- scope does not track it (never resolved here, owned by a singleton, already released, or the scope is closed).
---@param instance table  a closable transient resolved through this scope
function ServiceScope:release(instance)
  if type(instance) ~= "table" and type(instance) ~= "userdata" then
    argument_error("release", "instance must be a table or a userdata")
  end
  if not self._released[instance] then
    error(ContainerError("container: release of an instance that this service scope does not track"), 2)
  end
  self._released[instance] = nil
  untrack(self, instance)
  getmetatable(instance).__close(instance, nil)
end

--- Closes the scoped services and the transients that define `__close`, in reverse order of creation. Idempotent. Every close is
--- attempted; the first error is raised afterwards, the others are in `context.suppressed`.
function ServiceScope:close()
  if self._closed then return end
  self._closed = true
  self._released = {}
  self._tracked = {}
  close_all(self._owned)
end

--- Supports `local scope <close> = container:open_scope()`.
function ServiceScope:__close() self:close() end

core.finalise(Container)
core.finalise(ServiceScope)

return { Container = Container, ServiceScope = ServiceScope }
