# `hecate-core`

> Object model (classes, traits, interfaces), error hierarchy, enumerations, value objects and Lua-version compatibility shims.

| | |
|---|---|
| Module | `hecate.core` |
| Rock | `hecate-core` |
| Layer | 0 — Foundation |
| Roadmap phase | 1 |
| Status | alpha — implemented in Phase 1; the declaration spelling is frozen (ADR 0007, owner decision of 2026-10-27) |
| Lua | 5.5 (`lua >= 5.5, < 5.6`) |
| Depends on | none |
| Used by | `cli`, `config`, `container`, `doc`, `hecate`, `http`, `json`, `kernel`, `log`, `migration`, `mongodb`, `mysql`, `net`, `openapi`, `orm`, `postgresql`, `query`, `reactor`, `redis`, `router`, `schema`, `security`, `sql`, `sqlite`, `sqlserver`, `template`, `test`, `websocket` |
| Native code | none |
| Specification | [object-model.md](../../docs/architecture/object-model.md) |
| Decisions | [ADR 0001](../../docs/adr/0001-lua-5.5-as-sole-target.md), [ADR 0004](../../docs/adr/0004-academic-vocabulary.md), [ADR 0007](../../docs/adr/0007-object-model.md), [ADR 0018](../../docs/adr/0018-error-signalling.md) |
| Agent | [`pkg-core`](../../.claude/agents/pkg-core.md) |
| Repository | read-only mirror `hecate-framework/hecate-core`, generated from this directory (ADR 0017) |

## Responsibilities

- `class`, `trait`, `interface`, `finalise`: single inheritance, flat trait composition with explicit conflict resolution, conformance checks at finalisation
- inherited metamethods including `__close`, `__eq`, `__lt`, `__tostring`, `__call`
- introspection used by container, kernel, orm, doc (`name`, `superclass`, `traits`, `interfaces`, `is_instance_of`)
- `Error` hierarchy with cause chaining, stable `code`, context, optional traceback
- `enumeration` and `value_class` (frozen, structurally compared)
- `hecate.core.compat`: shims for functions differing between Lua versions

## Non-goals

- multiple inheritance
- runtime-enforced visibility (convention + linter only)
- any I/O

## Standards and references

- Schärli et al., *Traits: Composable Units of Behaviour* (2003)

## Public API

All names are fields of `require "hecate.core"`.

Declaration spelling (ADR 0007):

```lua
local core = require "hecate.core"

local Comparable = core.interface("Comparable", { "compare" })
local Timestamped = core.trait("Timestamped", {
  touch = function(self) self.updated_at = os.time() end,
})

---@class Money
local Money = core.class("Money", nil, { traits = { Timestamped }, implements = { Comparable } })
function Money:init(amount, currency) self.amount, self.currency = amount, currency end
function Money:compare(other) return self.amount - other.amount end
core.finalise(Money)
```

| Name | Description |
|---|---|
| `class(name, superclass?, options?)` | Declares a class; options `traits`, `implements`, `fallback_provides` (names an `__index` fallback provides; they satisfy conformance checks). Instantiate with `Class(...)` after finalisation (calls `init`). |
| `finalise(class)` | Resolves traits and interfaces, flattens members into the class table; one `ConformanceError` lists every problem. Idempotent. |
| `allocate(class)` | Returns a new empty instance of a finalised class without calling `init` (metatable set, so methods, inherited members, metamethods, `class_of` and `is_instance_of` work). The only way to create an instance without `Class(...)`, for code that fills attributes from data it has validated (schema `build`, ORM). `ArgumentError` for a non-class or a `value_class` (use `instantiate_value`); `ConformanceError` for a class not finalised, as `Class(...)`. |
| `instantiate_value(class, fields)` | Returns a frozen instance of a finalised `value_class` built from a table of attributes (copied, not adopted) without calling `init`, with the same freezing as construction: fields read normally, writes refused, structural equality, `class_of` and `is_instance_of` work. For code that has validated the attributes (schema `build`). `ArgumentError` for anything but a value class (ordinary class, trait, interface, non-class) or a non-table; `ConformanceError` for a class not finalised. |
| `weak_table(mode?)` | New empty table with weak keys (`"k"`, default), weak values (`"v"`) or both (`"kv"`); raw `setmetatable` is reserved to core. For side tables keyed by instance (presence set, identity map). `ArgumentError` for another mode. |
| `trait(name, methods, options?)` | Declares a trait; options `traits` (composition), `requires`. A trait entry of a class may be `{ trait, exclude = {...}, alias = { old = "new" } }`; an alias that collides with another method of the same trait is a `ConformanceError`, a malformed `exclude` or `alias` an `ArgumentError`. |
| `interface(name, methods, options?)` | Declares an interface; option `extends`. |
| `value_class(name, superclass?, options?)` | Like `class`; instances are frozen after `init`, compared structurally by `__eq`. |
| `enumeration(name, names)` | Closed set of values (`Status.active`, `:values()`, `:names()`, `:contains(v)`, `:find(name)`, `:size()`). |
| `name`, `superclass`, `traits`, `interfaces`, `class_of`, `origin` | Introspection. |
| `is_instance_of(value, class)`, `implements(subject, interface_or_trait)` | Type tests. `value` may be of any type (a non-instance gives `false`); `class` must be a class, otherwise `ArgumentError`. |
| `is_class`, `is_value_class`, `is_trait`, `is_interface`, `is_enumeration`, `is_finalised` | Kind predicates. |
| `Error` and `ConfigurationError`, `ConformanceError`, `PreconditionError`, `ArgumentError`, `StateError`, `CancellationError`, `DeadlineExceededError`, `NonYieldableContextError`, `ClosedChannelError`, `NetworkError`, `IoError`, `ProtocolError`, `ValidationError`, `DatabaseError` | Error hierarchy: `Error("message")` or `Error { message =, cause =, context =, code = }`; fields `message`, `code`, `cause`, `context`, `traceback`; `root_cause()`; `__tostring` renders the chain. `PreconditionError` (the caller broke the contract of an operation) is the superclass of `ArgumentError` (a wrong argument) and `StateError` (the object is in a state that does not allow the operation: closed, already serving, not prepared; OQ-77); the others derive from `Error` directly. |
| `error_class(name, code, superclass?)` | Declares a finalised error subclass with a stable code. |
| `set_debug_mode(enabled)`, `is_debug_mode()` | Traceback capture on error creation. |
| `compat.table_create(narray?, nhash?)`, `compat.lua_version` | Lua-version shims. |

Precedence when finalising: class members, then trait members, then inherited members.
Two traits providing different functions under one name are a conflict unless the class
defines the member or one entry excludes it.

## Layout

```text
src/hecate/core/init.lua   public entry point (class, allocate, instantiate_value, weak_table, trait, interface,
                           introspection, error, value_class, enumeration, compat; internal/)
tests/unit/
examples/    benchmarks/dispatch.lua
```
