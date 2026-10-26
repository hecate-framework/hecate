# Engineering documentation

This directory holds the design of Hecate. The public, user-facing documentation lives
in [`../website`](../website).

| Document | Purpose |
|---|---|
| [vision.md](vision.md) | Goals, non-goals, principles, success criteria |
| [developer-experience.md](developer-experience.md) | The target experience for users of Hecate |
| [glossary.md](glossary.md) | Mandatory vocabulary |
| [roadmap.md](roadmap.md) | Phases, deliverables, exit criteria |
| [open-questions.md](open-questions.md) | Undecided points and research tasks |
| [architecture/](architecture/) | Specifications per area |
| [adr/](adr/) | Architecture Decision Records |

## Architecture specifications

- [overview.md](architecture/overview.md) — layers, packages, dependency rules, request lifecycle
- [object-model.md](architecture/object-model.md) — classes, traits, interfaces, errors
- [concurrency.md](architecture/concurrency.md) — reactor, coroutines, structured concurrency
- [http-and-routing.md](architecture/http-and-routing.md) — HTTP stack, router, kernel, filters
- [schemas-and-contracts.md](architecture/schemas-and-contracts.md) — refinement types, validation, OpenAPI
- [data-access.md](architecture/data-access.md) — SQL interfaces, drivers, query builder, ORM, migrations
- [logging.md](architecture/logging.md) — severities, loggers, records, sinks, ambient context
- [testing.md](architecture/testing.md) — test framework and contract testing
- [documentation.md](architecture/documentation.md) — website, i18n, generated references
- [cli-and-packaging.md](architecture/cli-and-packaging.md) — CLI, manifest, lockfile, LuaRocks, toolchains
- [versioning-and-distribution.md](architecture/versioning-and-distribution.md) — versions, Lua compatibility, Docker
- [coding-standards.md](architecture/coding-standards.md) — style and engineering rules
- [automation.md](architecture/automation.md) — CI/CD workflows and repository scripts
- [ai-assisted-development.md](architecture/ai-assisted-development.md) — context files, agents, commands, human gates
