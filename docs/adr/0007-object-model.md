# 0007 — One object model: classes, traits, interfaces

- **Status:** Accepted
- **Date:** 2026-10-11
- **Deciders:** project owner
- **Packages:** core, then all
- **Related:** [object-model.md](../architecture/object-model.md)

## Context

The owner wants object-oriented development to be the primary style. Lua offers
metatables, not classes; every Lua library reinvents classes differently, which is
precisely the "assembled modules" feeling Hecate avoids.

## Decision

- `hecate.core` provides the only class mechanism: single inheritance, traits with
  explicit conflict resolution, interfaces checked at finalisation, inherited
  metamethods, `__close` support, introspection.
- After finalisation, method lookup is a single table lookup (flattened methods).
- The declaration spelling is fixed by the first implementation in Phase 1 and then
  frozen: all packages and documentation use it identically. The implementing agent
  must update this ADR with the final spelling and promote it for review.

Scope confirmed by the owner (2026-10-11): the **complete** model from the first
implementation, traits included; the alternatives (adopting an existing class library,
or conventions on plain metatables) were rejected.

### Final spelling (Phase 1 implementation, for owner review and freeze)

```lua
local C = core.class("Name", Parent, { traits = { T, { U, exclude = {"m"}, alias = { n = "n2" } } },
                                       implements = { I } })
function C:init(...) end        -- constructor; super call: core.superclass(C).init(self, ...)
core.finalise(C)                -- required before `C(...)`
```

A class-level `__index` (function or table) is a fallback consulted after the flattened
lookup and inherited by subclasses. Names it is known to provide are declared with
`fallback_provides = { "name", ... }` in the class options: they satisfy interface and
trait `requires` checks, are not copied into the class, and declaring them without any
fallback is a `ConformanceError`. (`fallback_provides` rather than a bare `fallback`
because the option lists names, not the fallback itself.)

Traits: `core.trait(name, methods, { traits =, requires = })`; interfaces:
`core.interface(name, names, { extends = })`; value classes and enumerations:
`core.value_class(...)`, `core.enumeration(name, names)`. Open point: OQ-21.

- One mental model across framework and applications.
- `kernel` (controllers), `orm` (entities), `test` (test cases), `container`
  (services) build on it.

## Verification

`check-boundaries`: `setmetatable` outside `packages/core` requires a justification
comment `-- hecate: raw-metatable <reason>`; reviewed by the `core` agent.
