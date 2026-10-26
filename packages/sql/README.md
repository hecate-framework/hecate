# `hecate-sql`

> Driver-agnostic SQL interfaces: drivers, connections, prepared statements, transactions and savepoints, connection pool, type mapping, instrumentation.

| | |
|---|---|
| Module | `hecate.sql` |
| Rock | `hecate-sql` |
| Layer | Data |
| Roadmap phase | 4 |
| Status | specified — no code yet |
| Lua | 5.5 (`lua >= 5.5, < 5.6`) |
| Depends on | [`core`](../core), [`reactor`](../reactor), [`net`](../net), [`log`](../log), [`query`](../query) |
| Used by | `migration`, `mysql`, `orm`, `postgresql`, `sqlite`, `sqlserver` |
| Native code | none |
| Specification | [data-access.md](../../docs/architecture/data-access.md) |
| Decisions | [ADR 0014](../../docs/adr/0014-wire-protocol-drivers-in-lua.md) |
| Agent | [`pkg-sql`](../../.claude/agents/pkg-sql.md) |
| Repository | read-only mirror `hecate-framework/hecate-sql`, generated from this directory (ADR 0017) |

## Responsibilities

- interfaces `Driver`, `Connection`, `Statement`, `Transaction`, `Pool`, `ResultSet`
- connection URLs
- pool with deadlines, health checks, lifetimes
- uniform placeholders translated per driver
- `DatabaseError` hierarchy with SQLSTATE
- instrumentation hooks (log, timing)
- translators from the `query` expression tree to a dialect (PostgreSQL, MySQL, MariaDB, SQLite, SQL Server): submodules `hecate.sql.dialect.<name>`, selected from the descriptor (dialect name, server version, capabilities) that each driver reports; `connection:execute(expression)` translates, then sends text and bound parameters to the driver

## Non-goals

- building queries (see `query`); transport and wire protocols (see the drivers)

## Standards and references

- ISO/IEC 9075 (SQL)
- SQLSTATE codes

## Public API

*To be filled during implementation: list every exported class and function with a one-line
description, linking to the generated reference.*

## Layout (once implemented)

```text
src/hecate/sql/init.lua   public entry point
tests/unit/  tests/integration/  tests/fixtures/
examples/    benchmarks/
```
