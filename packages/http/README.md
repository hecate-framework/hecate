# `hecate-http`

> HTTP/1.1 server and client with a message model following RFC 9110 semantics.

| | |
|---|---|
| Module | `hecate.http` |
| Rock | `hecate-http` |
| Layer | 2 — Protocol |
| Roadmap phase | 2 |
| Status | specified — no code yet |
| Lua | 5.5 (`lua >= 5.5, < 5.6`) |
| Depends on | [`core`](../core), [`reactor`](../reactor), [`net`](../net), [`json`](../json), [`log`](../log) |
| Used by | `hecate`, `kernel`, `websocket` |
| Native code | llhttp binding (ADR 0019) |
| Specification | [http-and-routing.md](../../docs/architecture/http-and-routing.md) |
| Decisions | [ADR 0003](../../docs/adr/0003-transparent-structured-concurrency.md) |
| Agent | [`pkg-http`](../../.claude/agents/pkg-http.md) |
| Repository | read-only mirror `hecate-framework/hecate-http`, generated from this directory (ADR 0017) |

## Responsibilities

- server: keep-alive, pipelining safety, limits (field size, content size, deadlines), streamed content, graceful shutdown
- message model: `Request`, `Response`, case-insensitive fields, content, media types, cookies
- client: connection pool, redirects, timeouts/deadlines, TLS, streaming
- multipart and URL-encoded content parsing

## Non-goals

- routing (see `router`)
- HTTP/2 and WebSocket in early phases

## Standards and references

- RFC 9110 (semantics)
- RFC 9112 (HTTP/1.1)
- RFC 6265 (cookies)
- RFC 7578 (multipart/form-data)

## Public API

*To be filled during implementation: list every exported class and function with a one-line
description, linking to the generated reference.*

## Layout (once implemented)

```text
src/hecate/http/init.lua   public entry point
tests/unit/  tests/integration/  tests/fixtures/
examples/    benchmarks/
csrc/        native sources
```
