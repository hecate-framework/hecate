# 0026 — Data access layering: abstract API in `query`, translators in `sql`

- **Status:** Proposed
- **Date:** 2026-10-26
- **Deciders:** project owner (direction agreed on 2026-10-26 in the review of #41, OQ-58); to be accepted by the owner
- **Packages:** query, sql, postgresql, mysql, sqlite, sqlserver, migration, orm
- **Related:** [data-access.md](../architecture/data-access.md), [ADR 0011](0011-orm-data-mapper.md), [ADR 0021](0021-rust-native-modules.md), OQ-58

## Context

The data-access specification had `query` build an expression tree and render it per dialect, `sql` define the
driver interfaces, and the drivers (`postgresql`, `mysql`, `sqlite`) speak a wire protocol. Two things were
unclear: who renders the tree to a dialect (the `query` README listed "dialect renderers"), and who owns the
database-schema (DDL) definition API that `migration` uses (the `query` README and `data-access.md` disagreed).

Forces: drivers must stay as fast as possible and may become native (ADR 0021), so they should only move bytes;
the query API should be one tool independent of the data source; every dialect (MySQL and MariaDB differ on
`RETURNING`, SQLite and PostgreSQL by version) needs a translation that depends on the server's capabilities.
How others split it: Entity Framework Core generates SQL in provider packages from provider-neutral operation
objects (queries and migrations); FluentMigrator has its own DDL builders independent of any ORM.

## Options considered

1. **Renderers in `query`** (the previous specification). `query` can render without a driver, but it grows with
   every dialect and is no longer a neutral API.
2. **Renderers in each driver.** One self-contained package per database, but drivers must know the tree, so
   they depend on `query`, and a native driver would have to embed a translator.
3. **Translators in `sql`, abstract API in `query`** (chosen). `query` knows no dialect and no data source;
   `sql` holds the translators; drivers do transport only.

## Decision

- `query` is a pure, dialect-free API: the immutable expression tree for queries and data manipulation, and the
  database-schema (DDL) definition API. It depends on `core` only.
- `sql` depends on `query`. It holds the translators from the expression tree to a dialect, as submodules
  `hecate.sql.dialect.<name>` (PostgreSQL, MySQL, MariaDB, SQLite; SQL Server later), in pure Lua, in the
  package `sql` (no separate package). A translation returns SQL text and bound parameters.
- The order of the layers is `core → query → sql → drivers`. `connection:execute(expression)` selects the
  translator from the connection's descriptor, translates, then sends text and parameters to the driver.
- A driver does transport only, whether written in Lua or native. It reports a descriptor: dialect name, server
  version and capabilities (for example `RETURNING`, transactional DDL). The dialect detection of `mysql`
  becomes this descriptor.
- `migration` only sequences and records migrations; the DDL it runs is built with `query` and translated by `sql`.
- The translation layer is an interface whose first implementations are SQL. A query language common to
  relational and non-relational stores (Redis commands, MongoDB documents and pipelines) is not promised; `redis`
  and `mongodb` stay clients, `mongodb` with its document mapper.
- Prose and identifiers say *database schema* for the DDL object, never "schema" alone (`hecate.schema`).

## Consequences

- Easier: one query API whatever the source; a new dialect is a submodule of `sql`; drivers stay small and can
  be replaced by native ones without touching translation; DML and DDL share one translation path.
- Harder: `sql` grows and gains a dependency on `query`; the `query` and `sql` READMEs, rockspecs, the
  dependency graph and `data-access.md` change (done with this ADR); the `Statement` and `Connection` interfaces
  must accept an expression as well as text; the descriptor must be specified when `sql` is implemented.
- Follow-ups (Phase 4): specify the descriptor and the capability names in `data-access.md`; the dialect
  translators and their tests belong to the `sql` and `query` roadmap items.

## Verification

`check-boundaries` enforces the dependency direction (`query` declares only `core`; `sql` declares `query`);
the dialect translators are tested against fixtures of expected SQL per dialect; review rejects SQL rendering in
a driver or in `query`.
