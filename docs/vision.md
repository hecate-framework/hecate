# Vision

## Purpose

Hecate makes Lua a serious choice for building HTTP APIs: fast, typed at the boundaries,
documented by construction, and pleasant to work with. It targets developers who would
otherwise reach for FastAPI, Symfony, NestJS or Spring, and who want comparable
structure with less weight and more throughput.

## Goals

1. **A complete ecosystem.** Runtime, HTTP, routing, validation, contracts, tests,
   documentation, database access, ORM, migrations, CLI and Docker images, all
   maintained together. Users should never need to assemble third-party libraries to
   build a conventional API.
2. **Coherence.** One object model, one error model, one configuration system, one
   logging system, one vocabulary, one version number. A developer who has learned one
   component can predict how the others behave.
3. **Contract-first by construction.** Declaring a route and its schemas is enough to
   obtain validation, OpenAPI 3.1 contracts, API reference documentation and contract
   tests. There is a single source of truth, and it is executable.
4. **Object-oriented and simple.** Serious applications are built from classes:
   controllers, services, repositories, entities. Small services can stay small with
   route modules. Both styles produce the same internal structures.
5. **Easy adoption.** One installer, one command to create a project, one command to
   install dependencies, one command to run. The Lua toolchain itself is managed by
   the CLI.
6. **Performance.** Throughput and latency competitive with the fastest dynamic-language
   frameworks, measured continuously.
7. **Exhaustive documentation.** Tutorials, how-to guides, reference and explanations,
   in several languages.

## Non-goals (for now)

- LuaJIT and Lua versions before 5.4. (5.4 is planned through source lowering.)
- HTML rendering in the first releases. The `template` package is planned; the first
  releases respond with JSON only.
- HTTP/2, HTTP/3 and WebSocket in the first releases (planned).
- Being a general-purpose application runtime outside HTTP services.

## Principles

- **Single source of truth.** Information is declared once and derived elsewhere.
- **Explicit over magical, terse over verbose.** No hidden global state, no implicit
  registration by side effect of `require`. But declarations stay short.
- **Academic vocabulary** (see [glossary.md](glossary.md)); standards keep their terms.
- **Fail early.** Configuration, route tables, schemas, container graphs and class
  conformance are validated at boot, not at the first request.
- **Replaceable parts behind interfaces.** Defaults are opinionated; every major
  component is reachable through an interface so it can be substituted.
- **Measured performance.** No optimisation without a benchmark; no regression without
  a decision.
- **Documentation is a deliverable.** A feature without reference docs is not done.

## Success criteria for 1.0

- From a clean machine, `hecate new` to a running, documented, tested API in under five
  minutes on Linux, macOS and Windows.
- A CRUD API backed by PostgreSQL written with Hecate is shorter than its FastAPI +
  SQLAlchemy equivalent and serves more requests per second on the same hardware.
- Every public API is covered by reference documentation; the website is available in
  at least English and French.
