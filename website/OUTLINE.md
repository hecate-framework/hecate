# Site map

Status markers: (P1) … (P5) = roadmap phase in which the page must exist. A page already
written is listed with its file in `website/en/`.

## Home

- Landing: what Hecate is, a 20-line example, performance numbers, Lua 5.5 badge (P3)

## Tutorials

0. Lua for Hecate developers: the language essentials needed by the framework (tables, metatables, coroutines, `<close>`, Lua 5.5 `global` declarations), linking to the official reference manual and to Lua Web Docs (luadocs.com) for depth (P3)
1. Installation and first API: `hecate new`, a route, validation, `/openapi.json`, a test (P3)
2. Controllers, services and the container (P3)
3. A CRUD API with PostgreSQL: entities, repositories, migrations, unit of work (P4)
4. Testing an API: test cases, fixtures, contract conformance, property tests (P3)
5. Deploying with Docker (P3)

## How-to guides

- Routing: path parameters, prefixes, reverse routing, 404/405 customisation (P2)
- Validation: refinement types, custom formats, unions, error formats (P2)
- Problem details: mapping domain errors to RFC 9457 responses (P2)
- Filters: authentication, CORS, compression, request identifiers (P2)
- Configuration per environment, secrets (P2)
- Concurrency: fork/join, select, deadlines, channels, protecting shared state (P2)
- Connect and serve over TCP: connect, accept loop, reader and writer, half-close, name resolution (P1; `how-to/connect-and-serve-over-tcp.md`)
- TLS client and server: system trust store, private authority, two-step accept, ALPN, mutual TLS, error reasons (P1; `how-to/tls-client-and-server.md`)
- Deadlines and cancellation on streams: what each cancelled operation leaves behind (P1; `how-to/deadlines-and-cancellation.md`)
- UDP, Unix sockets, named pipes and DNS (P1; `how-to/udp-pipes-and-dns.md`)
- Run child processes and pass connections between processes: `run_process`, `spawn`, the message pipe (P2; `how-to/run-processes-and-pass-connections.md`)
- Background work and offloading CPU-bound tasks (P2)
- Logging and request context (P2)
- Contracts: exporting, linting, diffing in CI (P3)
- Documentation of a project with `hecate doc` (P3)
- Database: connection pools, transactions and savepoints, raw SQL (P4)
- Migrations: writing, applying, rolling back (P4)
- ORM: associations, loading strategies, avoiding N+1 (P4)
- Redis: caching, publish/subscribe (P4)
- Multi-process deployment, graceful shutdown, health checks (P2)
- Packaging and publishing a library rock (P3)
- Migrating from FastAPI / Symfony / Express (P5)

## Reference (generated unless noted)

- Packages: one section per package, every public symbol (P2→)
- Landing page of the reference, listing the documented packages and the glossary (P1; `reference/index.md`)
- CLI: every command and option (P3)
- Manifest `hecate.project.lua` and lockfile (P3)
- Configuration keys (P2)
- Error codes (P2)
- Schema keywords and formats (P2)
- Compatibility matrix: Hecate × Lua × platforms (hand-written) (P3)
- Glossary (hand-written, public version, kept in step with `docs/glossary.md`) (P2)
- Relational algebra ↔ SQL correspondence (hand-written) (P4)

## Explanation

- Architecture and layers (P2)
- The object model: classes, traits, interfaces (P2)
- Concurrency model: reactor, coroutines, suspension points, structured concurrency (P2)
- The transport model: streams, suspension instead of callbacks, back-pressure, half-close, buffering, cancellation rules (P1; `explanation/transport-model.md`)
- TLS trust and security defaults: the operating system's verifier, what cannot be disabled, revocation and platform caveats (P1; `explanation/tls-trust-and-security.md`)
- Multi-process serving: share-nothing workers, listening strategies, message pipe, what exists today (P2; `explanation/multi-process-serving.md`)
- Contract-first design: one declaration, many derivations (P3)
- Data mapper and unit of work (P4)
- Performance: what makes Hecate fast, how it is measured (P3)
- Security model and defaults (P3)
- Design decisions (summaries of ADRs) (P3)

## Community

- Contributing, translating, code of conduct, release policy, roadmap (P3)
