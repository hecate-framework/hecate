# Data access

Packages: `sql`, `query`, `postgresql`, `mysql`, `sqlite`, `redis`, `migration`, `orm`,
later `mongodb`, `sqlserver`. Status: specification.

## Driver coverage

| Database | Package | Phase | Implementation |
|---|---|---|---|
| PostgreSQL | `postgresql` | 4 | Lua, frontend/backend protocol v3 |
| MySQL, MariaDB | `mysql` | 4 | Lua, client/server protocol (one package, dialect detection) |
| SQLite | `sqlite` | 4 | C binding (vendored amalgamation), thread pool |
| Redis (and compatible: Valkey, KeyDB) | `redis` | 4 | Lua, RESP3 (RESP2 fallback) |
| MongoDB | `mongodb` | 5 | Lua, OP_MSG + BSON codec |
| Microsoft SQL Server | `sqlserver` | 5 | Lua, TDS |
| Others (Cassandra/ScyllaDB, Oracle, ...) | — | later | by demand |

Network drivers are written in Lua on top of `hecate.net`, so they suspend
transparently and need no native build.

## `hecate.sql` — interfaces

Driver-agnostic interfaces (object-model interfaces, checked for conformance):

- `Driver`: connection factory from a URL or table configuration.
- `Connection`: `execute(sql, parameters)`, `query(sql, parameters)` returning a
  result set, `prepare(sql)`, `transaction(fn)`, `close()`; `<close>`-able.
- `Statement`: prepared statement, reusable.
- `Transaction`: `commit`, `rollback`, savepoints (`savepoint(name)`), isolation level,
  read-only flag; nested `transaction(fn)` calls create savepoints.
- `Pool`: bounded connection pool with acquisition deadline, health checks, maximum
  lifetime and idle time; `pool:with(fn)` lends a connection for the duration of `fn`.
- `ResultSet`: iteration over tuples, attribute metadata, affected count, last inserted
  identifier when the database supports it.

Parameters are always bound (never interpolated). The placeholder syntax exposed to
users is uniform (`$1` or `:name`, decided in implementation, see OQ list) and
translated per driver.

### Type mapping

Each driver documents a bidirectional mapping between database types and Lua values:
integers (64-bit), floats, decimals (as strings or a `Decimal` value class — never as
floats), booleans, text, binary, dates and timestamps (value classes with time zone),
UUID, JSON, arrays (PostgreSQL), `NULL` (a dedicated sentinel distinct from `nil` in
result tuples).

### Errors

`DatabaseError` subclasses: `ConnectionError`, `IntegrityViolationError`
(unique, foreign key, not null, check), `SerializationFailureError`, `DeadlockDetectedError`,
`SyntaxError`, ... with SQLSTATE and the driver's native code. Like every error class,
each ends with `Error` and its `code` is the full class name (`hecate.sql.IntegrityViolationError`).

### Instrumentation

Every query emits a structured log event (debug level) and timing metrics; slow-query
threshold configurable.

### Translation to a dialect

`sql` depends on `query` (not the reverse): it holds the translators from the expression tree
to a dialect (`hecate.sql.dialect.<name>`: PostgreSQL, MySQL, MariaDB, SQLite, SQL Server
later), producing SQL text plus bound parameters. A driver does transport only: it reports a
descriptor (dialect name, server version, capabilities such as `RETURNING`; this is what the
`mysql` dialect detection becomes) and sends final text and parameters, whether the driver is
written in Lua or native. `connection:execute(expression)` selects the translator from the
descriptor, translates, then sends. The translation layer is an interface whose first
implementations are SQL; a cross-paradigm query language for Redis or MongoDB is not
promised ([ADR 0026](../adr/0026-query-sql-layering.md), OQ-58 resolved).

## `hecate.query` — query builder

Expressions follow relational algebra; see the correspondence table in
[the glossary](../glossary.md#relational-algebra-and-sql).

```lua
-- illustrative
local users = query.relation "users"
local q = users
  :selection(users.active:equals(true))
  :projection(users.id, users.email)
  :ordering(users.created_at:descending())
  :limit(20)
```

- Builds an immutable expression tree that knows no dialect and no data source; `query`
  depends on `core` only. Rendering and execution belong to `sql` (below).
- Supports joins, aggregates, grouping, sub-queries, common table expressions,
  `INSERT`/`UPDATE`/`DELETE` with `RETURNING` where supported.
- Raw SQL fragments are allowed but must carry bound parameters.

## `hecate.orm` — object-relational mapping

Status: [ADR 0011](../adr/0011-orm-data-mapper.md) (Proposed; spike OQ-18 decides).

- **Data mapper**: entities are ordinary classes; persistence lives in mappers and
  repositories, not in entities.
- **Unit of work**: tracks new, modified and removed entities; `commit` computes the
  change set, orders operations by dependencies, and executes them in one transaction.
- **Identity map** per unit of work.
- **Mapping metadata** declared next to the entity class (`relation`, `attribute`,
  associations: `belongs_to`, `has_one`, `has_many`, `many_to_many`), validated at boot
  against the database schema produced by migrations where possible.
- **Loading**: explicit eager loading (`with { "orders" }`) is the default
  recommendation; lazy loading suspends transparently (accessing a relation that the
  first query did not load runs one more query), and the ORM warns in development when it
  detects an N+1 pattern (one extra query per loaded tuple). There is no promise of
  freedom from N+1 by default.
- **Repositories**: generic repository with typed finders; custom repositories derive
  from it.
- Entities can expose their representation schema for HTTP use, but the ORM never
  serialises entities to HTTP implicitly.

## `hecate.migration`

- Versioned migrations stored in the project (`migrations/`), each with `up` and
  `down`. Identifiers sortable by time.
- Expressed with a database-schema definition API (create relation, add attribute, index,
  constraint) rendered per dialect, plus raw SQL when needed. The API is owned by `query`
  (rendered by the `sql` translators) and only sequenced and recorded by `migration` ([OQ-58](../open-questions.md)).
- Each migration runs in a transaction when the database supports transactional DDL.
- Applied migrations are recorded in a dedicated relation; checksums detect edited
  migrations.
- CLI: `hecate migrate`, `hecate migrate rollback`, `hecate migrate status`,
  `hecate migrate new <name>`.
- Later: generation of a migration from the difference between ORM metadata and the
  current database schema.

## Redis and document databases

`redis` is a client (commands, pipelining, publish/subscribe, `MULTI`/`EXEC`, Lua
scripts), not an ORM. `mongodb` provides a client and a document mapper sharing the
unit-of-work vocabulary where it applies.
