# `hecate-core`

> Object model (classes, traits, interfaces), error hierarchy, enumerations, value objects and Lua-version compatibility shims.

| | |
|---|---|
| Module | `hecate.core` |
| Rock | `hecate-core` |
| Layer | 0 — Foundation |
| Roadmap phase | 1 |
| Status | alpha — implemented in Phase 1; API pending owner freeze (ADR 0007) |
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
| `trait(name, methods, options?)` | Declares a trait; options `traits` (composition), `requires`. A trait entry of a class may be `{ trait, exclude = {...}, alias = { old = "new" } }`. |
| `interface(name, methods, options?)` | Declares an interface; option `extends`. |
| `value_class(name, superclass?, options?)` | Like `class`; instances are frozen after `init`, compared structurally by `__eq`. |
| `enumeration(name, names)` | Closed set of values (`Status.active`, `:values()`, `:names()`, `:contains(v)`, `:find(name)`, `:size()`). |
| `name`, `superclass`, `traits`, `interfaces`, `class_of`, `origin` | Introspection. |
| `is_instance_of(value, class)`, `implements(subject, interface_or_trait)` | Type tests. |
| `is_class`, `is_trait`, `is_interface`, `is_enumeration`, `is_finalised` | Kind predicates. |
| `Error` and `ConfigurationError`, `ConformanceError`, `ArgumentError`, `CancellationError`, `DeadlineExceededError`, `NonYieldableContextError`, `ClosedChannelError`, `NetworkError`, `ProtocolError`, `ValidationError`, `DatabaseError` | Error hierarchy: `Error("message")` or `Error { message =, cause =, context =, code = }`; fields `message`, `code`, `cause`, `context`, `traceback`; `root_cause()`; `__tostring` renders the chain. |
| `error_class(name, code, superclass?)` | Declares a finalised error subclass with a stable code. |
| `set_debug_mode(enabled)`, `is_debug_mode()` | Traceback capture on error creation. |
| `compat.table_create(narray?, nhash?)`, `compat.lua_version` | Lua-version shims. |

Precedence when finalising: class members, then trait members, then inherited members.
Two traits providing different functions under one name are a conflict unless the class
defines the member or one entry excludes it.

## Layout

```text
src/hecate/core/init.lua   public entry point (class, trait, interface, introspection,
                           error, value_class, enumeration, compat; internal/)
tests/unit/
examples/    benchmarks/dispatch.lua
```
