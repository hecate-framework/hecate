# Architecture overview

## Layers

Packages are organised in layers. **A package may depend only on packages of strictly
lower layers** (or, for the data and tooling groups, on the layers listed). Cycles are
forbidden and checked in CI.

```mermaid
flowchart TB
  subgraph L0[Layer 0 — Foundation]
    core
  end
  subgraph L1[Layer 1 — Runtime]
    reactor --> core
    net --> reactor
    json --> core
    log --> reactor
  end
  subgraph L2[Layer 2 — Protocol]
    http --> net
    http --> json
    schema --> json
    router --> core
  end
  subgraph L3[Layer 3 — Framework]
    container --> core
    config --> schema
    openapi --> schema
    openapi --> router
    kernel --> http
    kernel --> router
    kernel --> schema
    kernel --> container
    kernel --> config
    kernel --> log
  end
  subgraph D[Data]
    sql --> net
    sql --> log
    query --> sql
    postgresql --> sql
    mysql --> sql
    sqlite --> sql
    redis --> net
    migration --> query
    orm --> query
    orm --> schema
  end
  subgraph T[Tooling]
    test --> kernel
    test --> openapi
    doc --> openapi
    cli --> kernel
  end
```

Edges show the main direct dependencies; transitive ones are omitted. Each package's
README lists its exact dependencies.

## Naming

- Directory: `packages/<name>/`
- Rock: `hecate-<name>` (the meta-rock is `hecate`)
- Lua module root: `hecate.<name>` (e.g. `require "hecate.router"`)
- The meta-module `hecate` re-exports the framework surface (classes, controllers,
  routes, problem details) so that typical application code needs one `require`.

## Native code policy

Hecate is Lua-first. Native code is used only where Lua cannot reach the required
performance or system access:

| Need | Native component | Decision |
|---|---|---|
| Asynchronous I/O | libuv through luv | ADR 0002 |
| HTTP/1.1 parsing | llhttp | OQ-6 |
| JSON | C codec | OQ-5 |
| TLS | OpenSSL 3 (or alternative) | OQ-4 |
| SQLite | SQLite amalgamation | data-access.md |
| Hashing for auth protocols (SHA-256, HMAC, PBKDF2) | provided by the TLS library binding | OQ-4 |

C code is C11, compiled with warnings as errors, tested under AddressSanitizer and
UndefinedBehaviorSanitizer on Linux, and must build with MSVC on Windows.

Database wire protocols (PostgreSQL, MySQL, Redis, MongoDB, TDS) are implemented in Lua
on top of `hecate.net`: they then cooperate with the reactor transparently and need no
per-platform builds.

## Request lifecycle

```mermaid
sequenceDiagram
  participant R as reactor
  participant H as http.Server
  participant K as kernel.Application
  participant Rt as router
  participant F as filters
  participant A as action
  R->>H: connection readable
  H->>H: parse request (llhttp)
  H->>K: dispatch(request) in a new coroutine and request scope
  K->>Rt: match(method, path)
  Rt-->>K: route + path parameters (or 404 / 405)
  K->>K: coerce and validate parameters and content (schema)
  K->>F: enter filter chain
  F->>A: invoke action (controller method or function)
  A-->>F: value, Response or problem
  F-->>K: result
  K->>K: serialise representation, validate response (development/test)
  K-->>H: Response
  H-->>R: write (suspends until flushed)
```

Every request runs in its own coroutine inside a **scope** (structured concurrency):
computations forked during the request are cancelled when the request completes or is
aborted. See [concurrency.md](concurrency.md).

## Boot sequence

1. Load configuration (layers, environment), validate it against its schema.
2. Build the container graph; detect missing bindings and cycles.
3. Load modules; collect controllers and route modules; build the route table.
4. Compile schemas; verify that every route's schemas are well-formed and that every
   controller action exists (interface conformance).
5. Compile the router (radix tree) and, when enabled, the OpenAPI document.
6. Start workers and listen.

Any failure in steps 1–5 aborts the boot with a precise diagnostic. Nothing is
validated lazily at the first request.
