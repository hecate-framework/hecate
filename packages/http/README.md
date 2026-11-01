# `hecate-http`

> HTTP/1.1 server and client with a message model following RFC 9110 semantics.

| | |
|---|---|
| Module | `hecate.http` |
| Rock | `hecate-http` |
| Layer | 2 — Protocol |
| Roadmap phase | 2 |
| Status | in progress — message model implemented (pure Lua); llhttp binding, server and client pending |
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

Implemented (message model, no I/O yet):

- `http.Fields`: case-insensitive, multi-valued, order-preserving fields (`add`, `set`, `get`, `get_all`, `combined`, `has`, `remove`, `count`, `lines`, `copy`); refuses CR, LF and NUL in values and non-token names.
- `http.MediaType`: `MediaType.parse` (nil and a reason on malformed input), `format`, `essence`, `suffix`, `matches`.
- `http.Status`: `reason`, `class`, `is_valid`, `forbids_content`.
- `http.Request`: `method`, `target`, `path`, `query`, `fields`, `content`, `parameters`, `scope`; `peer_address()`, `cookies()`, `media_type()`.
- `http.Response`: `status`, `reason`, `fields`, `content`; `set_cookie`, `is_successful`.
- `http.Cookie.parse` (the `Cookie` field, RFC 6265 section 4.2.1) and `http.SetCookie` (`format`).

Pending: llhttp binding, server, client, limits, multipart and URL-encoded content.

## Layout (once implemented)

```text
src/hecate/http/init.lua   public entry point
tests/unit/  tests/integration/  tests/fixtures/
examples/    benchmarks/
csrc/        native sources
```
