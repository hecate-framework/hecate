# Object model (`hecate.core`)

Status: specification; see [ADR 0007](../adr/0007-object-model.md) (Accepted).

Every Hecate component and every application built on Hecate uses this single object
model. No package may define its own class mechanism.

## Requirements

1. Classes with single inheritance, constructors and `super` calls.
2. **Traits** (Schärli et al.) for horizontal reuse: composition is flat, conflicts
   between traits are errors unless explicitly resolved (exclusion or aliasing).
3. **Interfaces**: named sets of required methods. Conformance is checked when the
   class is finalised, not at call time.
4. Metamethods (`__tostring`, `__eq`, `__lt`, `__le`, `__len`, `__call`, `__close`,
   `__index` fallbacks) are inherited correctly.
5. `__close` support so that resources (connections, transactions, scopes) can be bound
   to Lua 5.4+/5.5 `<close>` variables.
6. Introspection: class name, superclass, traits, interfaces, `is_instance_of`,
   `implements`. Needed by the container, the kernel and the documentation generator.
7. Method lookup cost equal to a plain metatable `__index` table lookup after class
   finalisation (methods are flattened into the class table; no chained lookups on the
   hot path).
8. LuaLS-friendly: the declaration pattern must let LuaLS infer types with
   `---@class Name : Parent` annotations.

## Proposed surface (illustrative)

```lua
local core = require "hecate.core"

local Comparable = core.interface("Comparable", { "compare" })

local Timestamped = core.trait("Timestamped", {
  touch = function(self) self.updated_at = os.time() end,
})

---@class Money
local Money = core.class("Money", nil, {
  traits     = { Timestamped },
  implements = { Comparable },
})

function Money:init(amount, currency)
  self.amount, self.currency = amount, currency
end

function Money:compare(other) ... end

core.finalise(Money)        -- conformance and conflict checks; flattening
```

A class-level `__index` is a fallback consulted after the flattened lookup (and inherited).
Members it is known to provide are declared in the class options,
`fallback_provides = { "compare" }`: an explicit list of names that counts as provided for
interface conformance and trait `requires`, is never copied into the class, and is an
error at finalisation when no fallback stands behind it.

The exact spelling (`core.class("Money", Parent, options)` versus a declarative table)
is settled in ADR 0007 during implementation. Whatever is chosen must be identical
across all packages.

## Visibility

Lua has no access control. Convention:

- Fields and methods prefixed with `_` are private to the class.
- They are annotated `---@private` or `---@protected` for LuaLS.
- The linter (Phase 0 tooling) reports external access to `_`-prefixed members.

## Value objects and immutability

`core.value_class` produces classes whose instances are frozen after construction
(writes raise an error) and compared structurally by `__eq`. Freezing must not cost
anything on reads.

## Errors

A single hierarchy rooted at `hecate.core.Error`:

- fields: `message`, `cause` (another error, for chaining), `context` (table),
  `traceback` (captured when created in debug mode);
- subclasses per domain: `ConfigurationError`, `ConformanceError`, `CancellationError`,
  `DeadlineExceededError`, `NetworkError`, `ProtocolError`, `ValidationError`,
  `DatabaseError` (with SQLSTATE when available), etc.;
- `__tostring` renders the chain;
- errors that cross the HTTP boundary map to problem details (RFC 9457) through an
  explicit mapping in the kernel, never by exposing internal messages by default.

The signalling convention is decided in [ADR 0018](../adr/0018-error-signalling.md):
failures raise error objects, expected absence returns `nil`.

## Enumerations

`core.enumeration("Status", { "active", "disabled" })` yields a closed set of values
with `__tostring`, membership tests and schema integration (`schema.enumeration(Status)`).

## Compatibility shims

`hecate.core.compat` exposes the few library functions that differ between Lua versions
(`table.create`, ...). Library code calls the shim, never the version-specific function
directly, so that the 5.4 build (ADR 0001) needs no source changes beyond lowering.
