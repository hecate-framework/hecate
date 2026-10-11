# `hecate-net`

> TCP/UDP streams, DNS resolution, buffered readers/writers and TLS, all suspending transparently.

| | |
|---|---|
| Module | `hecate.net` |
| Rock | `hecate-net` |
| Layer | 1 — Runtime |
| Roadmap phase | 1 |
| Status | specified — no code yet |
| Lua | 5.5 (`lua >= 5.5, < 5.6`) |
| Depends on | [`core`](../core), [`reactor`](../reactor) |
| Used by | `hecate`, `http`, `mongodb`, `mysql`, `postgresql`, `redis`, `sql`, `sqlserver`, `websocket` |
| Native code | TLS library binding (OQ-4) |
| Specification | [concurrency.md](../../docs/architecture/concurrency.md) |
| Decisions | [ADR 0002](../../docs/adr/0002-libuv-via-luv.md), [ADR 0003](../../docs/adr/0003-transparent-structured-concurrency.md) |
| Agent | [`pkg-net`](../../.claude/agents/pkg-net.md) |
| Repository | read-only mirror `hecate-framework/hecate-net`, generated from this directory (ADR 0017) |

## Responsibilities

- `TcpListener`, `TcpStream`, `UdpSocket`, Unix domain sockets / Windows named pipes
- `BufferedReader` (read line, read exact, read until) and `BufferedWriter`
- DNS resolution through libuv
- TLS client and server (SNI, ALPN, certificate verification, mutual TLS)
- back-pressure and per-operation deadlines

## Non-goals

- application protocols (HTTP lives in `http`)

## Standards and references

- RFC 8446 (TLS 1.3)
- RFC 6125 (service identity)

## Public API

*To be filled during implementation: list every exported class and function with a one-line
description, linking to the generated reference.*

## Layout (once implemented)

```text
src/hecate/net/init.lua   public entry point
tests/unit/  tests/integration/  tests/fixtures/
examples/    benchmarks/
csrc/        native sources
```
