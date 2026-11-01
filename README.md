<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="packages/doc/src/hecate/doc/theme/assets/brand/hecate-logo-horizontal-on-dark.svg">
    <img src="packages/doc/src/hecate/doc/theme/assets/brand/hecate-logo-horizontal.svg" alt="hecate" width="342" height="96">
  </picture>
</p>

<h3 align="center"><em>A modular, contract-first web API framework for Lua 5.5.</em></h3>

<p align="center">
  <img alt="status" src="https://img.shields.io/badge/status-early%20implementation-2F6F64?style=flat-square&labelColor=1C2766">
  <img alt="Lua" src="https://img.shields.io/badge/Lua-5.5-1C2766?style=flat-square&labelColor=1C2766&logo=lua&logoColor=white">
  <img alt="platforms" src="https://img.shields.io/badge/Linux%20%7C%20macOS%20%7C%20Windows-tested--in--CI-2F6F64?style=flat-square&labelColor=1C2766">
  <img alt="license" src="https://img.shields.io/badge/license-MIT-2F6F64?style=flat-square&labelColor=1C2766">
</p>

<p align="center">
  <a href="docs/vision.md"><b>Vision</b></a> ·
  <a href="docs/developer-experience.md"><b>Developer experience</b></a> ·
  <a href="docs/architecture/overview.md"><b>Architecture</b></a> ·
  <a href="docs/roadmap.md"><b>Roadmap</b></a> ·
  <a href="packages/README.md"><b>Packages</b></a> ·
  <a href="https://hecate.theandre.dev"><b>Website</b></a>
</p>

<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="docs/assets/readme-pattern-on-dark.svg">
    <img src="docs/assets/readme-pattern.svg" alt="" width="100%" height="96">
  </picture>
</p>

> [!NOTE]
> **Status: early implementation, not usable yet.** The foundations exist and are tested on
> Linux, macOS and Windows: the object model and errors (`core`), the asynchronous runtime
> (`reactor`), networking with TLS (`net`), the JSON codec (`json`), structured logging (`log`)
> and the documentation generator that builds the website (`doc`). The HTTP server, router,
> schemas, kernel, tooling and data access are specified in `docs/` and not written yet; the
> [roadmap](docs/roadmap.md) says what comes next.

Hecate is a complete ecosystem for building HTTP APIs in Lua: an asynchronous runtime,
an HTTP server, a router, schemas and validation, automatic OpenAPI contracts, a test
framework, a documentation generator, database drivers, an object-relational mapper and
a command-line tool that manages everything from the Lua toolchain to dependencies.

It is designed to feel like **one framework**, not like a collection of libraries glued
together: one version number, one set of conventions, one vocabulary, one CLI.

## Principles

1. **One framework, not an assembly.** Every component shares the same object model,
   error model, naming and release cycle.
2. **Contract-first.** A route and its schemas are declared once, as runtime data.
   Validation, OpenAPI contracts, API documentation and contract tests derive from it.
3. **Object-oriented, simple by choice.** Classes, traits and interfaces for serious
   code; lightweight route modules remain available for small services. Both compile to
   the same structures.
4. **Transparent concurrency.** Actions read like sequential code. I/O suspends the
   current coroutine; explicit primitives (`fork`, `join`, `select`, `deadline`) exist
   for intended concurrency.
5. **Academic vocabulary.** Names follow the literature (future, reactor, refinement
   type, relation, unit of work), not the idioms of other languages.
6. **Performance is measured.** Benchmarks run in CI; regressions block releases.
7. **Documentation is part of the product.** No feature ships without reference
   documentation.
8. **Cross-platform.** Linux is the production target; macOS and Windows are supported development platforms, tested in CI.

See [docs/vision.md](docs/vision.md) and the target
[developer experience](docs/developer-experience.md).

## Components

| Layer | Packages |
|---|---|
| Foundation | [`core`](packages/core) |
| Runtime | [`reactor`](packages/reactor) · [`net`](packages/net) · [`json`](packages/json) · [`log`](packages/log) |
| Protocol | [`http`](packages/http) · [`schema`](packages/schema) · [`router`](packages/router) · [`websocket`](packages/websocket) |
| Framework | [`container`](packages/container) · [`config`](packages/config) · [`kernel`](packages/kernel) · [`openapi`](packages/openapi) · [`security`](packages/security) · [`template`](packages/template) |
| Data | [`sql`](packages/sql) · [`query`](packages/query) · [`postgresql`](packages/postgresql) · [`mysql`](packages/mysql) · [`sqlite`](packages/sqlite) · [`redis`](packages/redis) · [`mongodb`](packages/mongodb) · [`sqlserver`](packages/sqlserver) · [`migration`](packages/migration) · [`orm`](packages/orm) |
| Tooling | [`cli`](packages/cli) · [`test`](packages/test) · [`doc`](packages/doc) |
| Meta | [`hecate`](packages/hecate): the standard edition in one dependency |

The full catalogue, with status and dependencies, is in [packages/README.md](packages/README.md).

## Lua compatibility

| Hecate | Lua | Status |
|---|---|---|
| 0.x | 5.5 | early implementation |
| future | 5.4 | planned, through source lowering ([ADR 0001](docs/adr/0001-lua-5.5-as-sole-target.md)) |

The supported Lua version is always visible: in `hecate version`, in every rockspec,
in Docker image tags and at the top of every release note.
See [versioning and distribution](docs/architecture/versioning-and-distribution.md).

## Repository layout

```text
docs/          Engineering documentation: vision, architecture, ADRs, roadmap, spikes
packages/      One directory per component; each becomes a LuaRocks rock
tools/         Repository scripts: bootstrap, checks, generators, release (Lua)
.claude/       Claude Code agents (one per package + reviewers), commands, settings
.github/       Workflows, issue templates, labels
website/       Public documentation site (multilingual)
docker/        Base images
benchmarks/    Performance suite
examples/      Reference applications
```

## Repositories

This monorepo is where Hecate is developed. Each package is also published to its own
**read-only mirror** (`hecate-<name>`), from which rocks are built; issues and pull
requests belong here ([ADR 0017](docs/adr/0017-monorepo-with-read-only-mirrors.md)).

## Contributing

Read [CONTRIBUTING.md](CONTRIBUTING.md). AI-assisted development follows
[CLAUDE.md](CLAUDE.md) and [docs/architecture/ai-assisted-development.md](docs/architecture/ai-assisted-development.md);
a documentation map for LLMs is in [llms.txt](llms.txt).

## License

[MIT](LICENSE) © Théandre Bourry

Organisation: [hecate-framework](https://github.com/hecate-framework) · Website (provisional):
<https://hecate.theandre.dev> · Contact: <theandre.bourry@ik.me>
