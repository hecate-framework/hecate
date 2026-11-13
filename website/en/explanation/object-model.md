---
description: Why hecate has one object model, and how it works - classes with single inheritance, traits with explicit conflicts, interfaces checked at finalisation, value classes and the error hierarchy.
hecate: "0.x"
lua: "5.5"
order: 7
---

# The object model: classes, traits, interfaces

This page explains the object model of `hecate.core` and the reasons for its shape. It is written for hecate 0.x and
Lua 5.5. The decision is ADR 0007.

## Why one object model

Lua has metatables, not classes. Every Lua library builds its own classes on them, each differently. An application
assembled from several libraries then mixes several ideas of what an object is.

hecate has one object model: `hecate.core`. Controllers, services, errors, problem details, schemas bound to classes,
and the classes of your application all use it. No package defines a class mechanism of its own.

## The parts

The object model has five parts:

| Part | What it is |
|---|---|
| [class](../reference/glossary.md#object-model-and-architecture) | a template for objects; single inheritance from one [superclass](../reference/glossary.md#object-model-and-architecture) |
| [trait](../reference/glossary.md#object-model-and-architecture) | a reusable set of methods composed into a class |
| [interface](../reference/glossary.md#object-model-and-architecture) | a named list of methods that a class must have |
| value class | a class whose instances are frozen and compared by value |
| [enumeration](../reference/glossary.md#object-model-and-architecture) | a closed set of named values |

The sections below take them one at a time, starting with the class.

## Declaring a class

A class is declared, given methods, then finalised. Here is a small one:

<!-- example: packages/core/examples/hecate.core.class.lua -->
```lua
-- Declares a class with a method, finalises it, then uses it.
local core = require("hecate.core")

local Money = core.class("Money")

function Money:init(amount)
  self.amount = amount
end

function Money:double()
  return Money(self.amount * 2)
end

core.finalise(Money)

print(Money(21):double().amount)
-- Prints: 42
```

The spelling is the same everywhere:

- `core.class(name, superclass?, options?)` declares the class.
- Methods are written on the class table.
- `init` is the constructor.
- `core.finalise(Class)` comes before the first instance.

`Class(...)` creates an instance and calls `init`. A method of the superclass is called explicitly:
`core.superclass(Money).init(self, ...)`.

## Finalisation

[Finalisation](../reference/glossary.md#object-model-and-architecture) is the step that turns a declaration into a
class ready to use. `core.finalise` does three things:

1. It composes the traits and checks their conflicts.
2. It checks [conformance](../reference/glossary.md#object-model-and-architecture): every method that an interface
   or a trait requires is present.
3. It flattens the members of the superclass and of the traits into the class table.

Every problem is reported at once, in one `ConformanceError`, and before any instance exists. A class that forgets a
method of its interface fails when the program loads it. It does not wait until a request finally calls the method.

This is the same choice as the boot of an application: what can be checked early is checked early.

Flattening is a performance choice. After finalisation, finding a method is one lookup in the class table, whatever
the depth of the inheritance. That is the cost of a plain metatable. There is no chain of `__index` tables to walk
on every call.

## Traits instead of multiple inheritance

A class has one superclass. To share behaviour across unrelated classes, hecate uses traits (Schärli, Ducasse,
Nierstrasz and Black, 2003), not multiple inheritance or mixins. A trait is a reusable set of methods that
finalisation copies into the class.

The composition of traits is flat, and its conflicts are errors. When two traits give different functions under the
same name, finalisation fails:

```lua
local core = require("hecate.core")

local Greeting = core.trait("Greeting", {
  hello = function() return "hello" end,
})
local Gesture = core.trait("Gesture", {
  hello = function() return "a wave" end,
})

-- Both traits provide `hello`: finalisation refuses the class.
local Clash = core.class("Clash", nil, { traits = { Greeting, Gesture } })
local ok, err = pcall(core.finalise, Clash)
print(ok, core.name(err))
-- Prints: false	ConformanceError
```

The class resolves the conflict itself, in one of two ways:

- It defines the member.
- It excludes the member from one trait (`{ Trait, exclude = { "name" } }`), possibly keeping it under another name
  (`alias = { name = "other_name" }`).

```lua
-- Exclude `hello` from one trait, and keep it under another name.
local Host = core.class("Host", nil, {
  traits = { Greeting, { Gesture, exclude = { "hello" }, alias = { hello = "wave" } } },
})
core.finalise(Host)
print(Host():hello(), Host():wave())
-- Prints: hello	a wave
```

Mixins resolve such a clash silently, by the order in which they are applied. A trait makes you decide.

When names collide, a fixed precedence applies. The members of the class win over those of its traits, which win
over the inherited ones.

A trait can also declare the methods it needs from its class (`requires`). They are checked at finalisation, like the
methods of an interface.

## Interfaces

An interface names a set of methods. `implements = { Comparable }` makes finalisation check that the class has them.
`core.implements(Class, Comparable)` answers the same question at run time.

This example declares an interface, a trait that relies on it, a class that uses both, and a value class (next
section):

<!-- example: packages/core/examples/hecate.core.trait.lua -->
```lua
-- A trait adds methods to a class; an interface lists the methods a class
-- must have. Both are checked once, when the class is finalised.
local core = require("hecate.core")

local Comparable = core.interface("Comparable", { "compare" })
local Ordered = core.trait("Ordered", {
  less_than = function(self, other) return self:compare(other) < 0 end,
}, { requires = { "compare" } })

local Money = core.class("Money", nil, {
  traits = { Ordered }, implements = { Comparable },
})
function Money:init(cents) self.cents = cents end
function Money:compare(other) return self.cents - other.cents end
core.finalise(Money)

print(Money(150):less_than(Money(200)), core.implements(Money, Comparable))
-- Prints: true	true

-- A class that misses a required method fails at finalisation, not later.
local Broken = core.class("Broken", nil, { implements = { Comparable } })
local ok, err = pcall(core.finalise, Broken)
print(ok, core.name(err))
-- Prints: false	ConformanceError

-- A value class is frozen after `init` and compared by value.
local Point = core.value_class("Point")
function Point:init(x, y) self.x, self.y = x, y end
core.finalise(Point)
print(Point(1, 2) == Point(1, 2))
-- Prints: true
local written, refusal = pcall(function() Point(1, 2).x = 3 end)
print(written, core.name(refusal))
-- Prints: false	ConformanceError
```

The kernel, the container and the documentation generator rely on these declarations. They also use the other
introspection functions: `core.name`, `core.superclass` and `core.is_instance_of`.

The word *contract* is reserved for API contracts. An interface is a check of a class, not of an HTTP API.

## Values and immutability

`core.value_class` declares a class whose instances are frozen after `init`. A write raises an error, and `==`
compares two instances attribute by attribute. The end of the example above shows both.

A [value object](../reference/glossary.md#object-model-and-architecture) is an immutable object compared by value,
such as an amount of money or a date range. Frozen, it is safe to share between computations.

Freezing costs nothing on reads. A read is still a table lookup, and no function runs on it.

## Errors are classes too

`hecate.core.Error` is the root of one error hierarchy. Failures raise these objects. An expected absence returns
`nil` instead.

The main classes of the hierarchy are:

- `PreconditionError`, when the caller broke the [precondition](../reference/glossary.md#object-model-and-architecture)
  of an operation: what the caller must ensure. It has two subclasses:
  - `ArgumentError`, a wrong argument;
  - `StateError`, an object used in the wrong state, such as a closed client or a server that already serves.
- `ValidationError`, `CancellationError`, `NetworkError` and the others.

An error has a `message`, a stable `code`, a `context` table and a `cause`. `tostring` renders the
[cause chain](../reference/glossary.md#object-model-and-architecture), the errors linked by `cause`.

Problem details are a subclass of `Error`. That is why an action can raise `hecate.problem.NotFound { ... }`, and the
kernel can tell it from any other error. See
[Map domain errors to problem details](../how-to/map-domain-errors-to-problem-details.md).

## Conventions instead of enforcement

Lua has no access control. A member whose name starts with `_` is private to its class by convention. It is
annotated `---@private` or `---@protected` for the type checker.

The declarations are written so that the Lua language server infers the types from `---@class Money : Superclass`
annotations.

A class may also declare a fallback `__index` for names it computes. The names that the fallback provides are listed in
`fallback_provides`, so that finalisation can count them for conformance.

## See also

- [Architecture and layers](architecture-and-layers.md)
- Reference: [`hecate.core`](../reference/core/index.md)
