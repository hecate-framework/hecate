# 0011 — ORM follows Data Mapper + Unit of Work

- **Status:** Proposed
- **Date:** 2026-10-11
- **Packages:** orm, query, migration
- **Related:** [data-access.md](../architecture/data-access.md), OQ-18 (spike pending: the owner decides on its report)

## Context

Two main patterns (Fowler, PoEAA): Active Record (entities persist themselves) and Data
Mapper (entities are plain objects; a mapper persists them). The owner works with
Symfony/Doctrine and wants a serious object-oriented framework.

## Decision

Data Mapper with Unit of Work, Identity Map and repositories. Entities are classes of
the core object model, unaware of the database. Metadata declares the relation and
attributes. Queries go through `hecate.query` (relational algebra vocabulary).

## Consequences

- Testable domain objects; explicit transactions; predictable flushing order.
- More concepts than Active Record; documentation must teach them progressively.

## Verification

ORM test suite runs against PostgreSQL, MySQL, MariaDB and SQLite in CI.
