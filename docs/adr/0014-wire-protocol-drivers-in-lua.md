# 0014 — Network database drivers implement wire protocols in Lua

- **Status:** Accepted
- **Date:** 2026-10-11
- **Deciders:** project owner
- **Packages:** postgresql, mysql, redis, mongodb, sqlserver
- **Related:** [data-access.md](../architecture/data-access.md)

## Context

C client libraries (libpq, libmysqlclient) block or require integrating their own
event handling with libuv per platform. Transparent suspension (ADR 0003) needs drivers
whose I/O goes through `hecate.net`.

## Decision

Network drivers implement their wire protocols in Lua on top of `hecate.net`:
PostgreSQL frontend/backend protocol v3, MySQL client/server protocol (MariaDB variants
detected), RESP3, MongoDB OP_MSG + BSON, TDS. Cryptographic needs (SCRAM-SHA-256,
`caching_sha2_password`) use the TLS binding's primitives. SQLite (in-process library)
is the exception: C binding executed on the libuv thread pool.

### Performance condition

Accepted on the condition that performance is acceptable (owner, 2026-10-11):

- Phase 4 benchmarks (`db-single`, `db-multiple`, `db-updates`) compare each Lua driver
  with the reference client of another ecosystem on the same machine.
- If the protocol code is a bottleneck, the remedy is **native accelerators** for the
  hot paths only (row decoding, type codecs, message framing), exposed as small C
  functions called by the Lua state machine, recorded in a new ADR. Network I/O stays
  in `hecate.net`, so transparent suspension is preserved. A full C rewrite of a driver
  is not the default remedy.

### Prior art in other ecosystems

Most ecosystems implement database protocols in their own language rather than binding
the vendor C library: Npgsql (C#, PostgreSQL) is fully managed code; pgx (Go) and
pgJDBC (Java) are written in Go and Java; node-postgres is JavaScript with an optional
libpq binding. Python's asyncpg implements the protocol itself and compiles the hot
parts with Cython, which is the model for the accelerator remedy above.

## Consequences

- No per-platform native builds for network drivers; uniform behaviour and tooling.
- Protocol correctness must be tested against real servers (service containers in CI,
  several server versions).

## Verification

Integration matrix in CI (`integration.yml`): each driver against at least the two
latest major versions of its server.
