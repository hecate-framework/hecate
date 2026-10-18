---
description: A modular, contract-first web API framework for Lua 5.5.
hecate: "0.x"
lua: "5.5"
layout: home
actions: ["Read the glossary | reference/glossary | primary", "Source code | https://github.com/hecate-framework/hecate"]
---

# hecate

hecate is a complete ecosystem for building HTTP APIs in Lua: an asynchronous runtime, an
HTTP server, a router, schemas and validation, automatic OpenAPI contracts, a test
framework, a documentation generator, database drivers, an object-relational mapper and a
command-line tool.

::: note Status
The project is at the specification stage: the design exists and the implementation is
under way, package by package. This site grows with it. The pages follow the Diátaxis
structure: tutorials, how-to guides, reference and explanation.
:::

## Principles

- **One framework, not an assembly.** Every component shares the object model, the error
  model, the naming and the release cycle.
- **Contract-first.** A route and its schemas are declared once, as runtime data.
  Validation, OpenAPI contracts, API documentation and contract tests derive from it.
- **Transparent concurrency.** Handlers read like sequential code; input and output
  suspend the running coroutine.
