# `hecate-http`

> HTTP/1.1 server and client with a message model following RFC 9110 semantics.

| | |
|---|---|
| Module | `hecate.http` |
| Rock | `hecate-http` |
| Layer | 2 — Protocol |
| Roadmap phase | 2 |
| Status | in progress — message model and llhttp parser binding implemented; server and client pending |
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

Implemented (parser, needs the native module: `lua tools/run.lua build-native http`; `require("hecate.http.parser")`, not loaded by `require("hecate.http")`):

- `http.parser` (`Parser.request(options)`, `Parser.response(options)`): the incremental llhttp binding (ADR 0019; llhttp's lenient flags stay off and none is reachable). `feed(chunk)` returns the events (`head`, `data`, `complete` with optional trailers, `upgrade`) and a `ParseError` for malformed input or an exceeded limit; `finish()` for the end of the connection; `skip_body()` for the final response to HEAD (an interim 1xx does not consume it); `close()` releases the memory. Events before a failure are delivered only for messages that completed. A failed parser, and a parser after an upgrade, return the same error to every later call (`kind` `upgraded` after an upgrade).
- Accepted: HTTP/1.0 and HTTP/1.1 only; RTSP and ICE (their methods, protocols and versions) are refused, and so is the chunked transfer coding in HTTP/1.0.
- `ParseError`: `context.reason`, `context.code`, `context.kind` (a stable identifier for the binding's own refusals), `context.position` (offset in the chunk of the failing call), `context.status` (400, 414 for the target, 431 for fields and heads).
- Limits with safe defaults, each an integer from 1 to 16777216 (an unknown option is an `ArgumentError`): `max_target_size` 8192, `max_field_size` 8192 (a name, a value, a reason phrase), `max_head_size` 65536 (raw bytes of a section: the head with its whitespace and leading empty lines, the bytes between two content chunks, the trailer section), `max_fields` 100, `max_events` 1024 (events recorded per native call; `feed` continues by itself). Feed chunks no larger than the read buffer: `feed` returns every event of the chunk in one list.
- The server must answer 400 to an HTTP/1.1 request without exactly one `Host` field (RFC 9112 section 3.2): the parser only exposes the fields (roadmap, `http` item).
- Known llhttp behaviour kept as is: more than one space between the method and the target is accepted (no smuggling effect); a leading CRLF before a request line is ignored (RFC 9112 section 2.2).
- The third-party sources are vendored in `csrc/vendor/` (llhttp 9.4.3, MIT; `VENDORED.md`). A libFuzzer target (`fuzz parse`) feeds random bytes split at random sizes; `sanitize http` runs the tests under ASan and UBSan.

Pending: server, client, request-level limits (content size, deadlines), multipart and URL-encoded content.

## Layout (once implemented)

```text
src/hecate/http/init.lua   public entry point
tests/unit/  tests/integration/  tests/fixtures/
examples/    benchmarks/
csrc/        native sources
```
