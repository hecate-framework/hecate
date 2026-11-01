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

Implemented (server, needs the native module): `http.Server(handler, options)`, `server:listen()` (*suspends*, returns the listener), `server:serve(listener?)` (*suspends*), `server:shutdown(grace?)` (*suspends*), `server:local_address()`, `Server.DEFAULTS`; also `http.ContentReader`, `http.ContentError` and `http.problem`.

- One coroutine per connection, and per request one scope (`request.scope`) with one coroutine running the handler; a connection serves its requests in order, so pipelined responses come in request order; keep-alive and `Connection: close` (HTTP/1.0 closes unless it asks to keep alive); `Date` field; `Expect: 100-continue` (sent when the handler first reads the content; any other expectation: 417; a handler that never reads closes the connection after its answer); 400 for an HTTP/1.1 request without exactly one `Host`; the parser's `context.status` (400, 414, 431); 501 for an `Upgrade` or `CONNECT` request; the parser is fed chunks of at most 16 KiB and closed when the connection ends.
- Errors are RFC 9457 problem details (`application/problem+json`, `type` `about:blank`) with a fixed `detail` chosen by status or by the class of the failure: a handler failure, a transport or network failure (`reactor.TransportError`: never an address, an errno or `context.attempts`), a parser failure. The text of an error never reaches the client; `on_error(err)` receives it.
- Request content is a stream: `request:content_reader()` (`read()` chunk by chunk, `read_all(limit?)`, `is_finished()`) and `request:read_content(limit?)` (the whole content). It is read when the handler asks; what the handler leaves unread is drained (up to `max_content`) so the next request can be parsed. Over `max_content` it is a 413 (`ContentError`; with a `Content-Length` over the limit the handler does not run). Naming: OQ-68.
- Response content is nil, a string (`Content-Length`), a table (JSON, `Content-Type: application/json` unless set) or a function `content(write, flush)` that streams: chunked coding, or the raw bytes when the handler declared a `Content-Length`, or close-delimited for HTTP/1.0. HEAD, 1xx, 204 and 304 never carry content; the framing fields of the handler (`Content-Length`, `Transfer-Encoding`, `Connection`) are replaced by the server's own.
- `listen` binds a NUMERIC address: the option `host` defaults to `127.0.0.1` (loopback only) and a name is an `ArgumentError`; every interface is `0.0.0.0` or `::` (OQ-69).
- Safe defaults (`Server.DEFAULTS`, each an option): `max_connections` 1024 (the others wait in the backlog), `max_content` 1048576 bytes, `head_timeout` 10 s (from the first byte of a head; then 408), `idle_timeout` 60 s (between requests; the connection closes silently), `content_timeout` 30 s (between two reads of content; then 408), `write_timeout` 30 s (a write to the client; then the connection closes), `backlog` 128, `port` 8080, parser limits as listed below (`parser` option).
- `shutdown(grace)` (default 30 s) stops accepting, closes the connections that wait for a request, lets each request in flight finish (`Connection: close`), then returns; when the grace expires the remaining requests are cancelled. `serve` returns once every connection has ended.
- Not yet: TLS (with its handshake limits), the full limits suite (a head that arrives in pieces after a pipelined request is held to `idle_timeout`, not `head_timeout`), client.

Implemented (parser, needs the native module: `lua tools/run.lua build-native http`; `require("hecate.http.parser")`, not loaded by `require("hecate.http")`):

- `http.parser` (`Parser.request(options)`, `Parser.response(options)`): the incremental llhttp binding (ADR 0019; llhttp's lenient flags stay off and none is reachable). `feed(chunk)` returns the events (`head`, `data`, `complete` with optional trailers, `upgrade`) and a `ParseError` for malformed input or an exceeded limit; `finish()` for the end of the connection; `skip_body()` for the final response to HEAD (an interim 1xx does not consume it); `close()` releases the memory. Events before a failure are delivered only for messages that completed. A failed parser, and a parser after an upgrade, return the same error to every later call (`kind` `upgraded` after an upgrade).
- Accepted: HTTP/1.0 and HTTP/1.1 only; RTSP and ICE (their methods, protocols and versions) are refused, and so is the chunked transfer coding in HTTP/1.0.
- `ParseError`: `context.reason`, `context.code`, `context.kind` (a stable identifier for the binding's own refusals), `context.position` (offset in the chunk of the failing call), `context.status` (400, 414 for the target, 431 for fields and heads).
- Limits with safe defaults, each an integer from 1 to 16777216 (an unknown option is an `ArgumentError`): `max_target_size` 8192, `max_field_size` 8192 (a name, a value, a reason phrase), `max_head_size` 65536 (raw bytes of a section: the head with its whitespace and leading empty lines, the bytes between two content chunks, the trailer section), `max_fields` 100, `max_events` 1024 (events recorded per native call; `feed` continues by itself). Feed chunks no larger than the read buffer: `feed` returns every event of the chunk in one list.
- Known llhttp behaviour kept as is: see "Conformance and known limits" below (a leading CRLF before a request line is ignored, RFC 9112 section 2.2).
- The third-party sources are vendored in `csrc/vendor/` (llhttp 9.4.3, MIT; `VENDORED.md`). A libFuzzer target (`fuzz parse`) feeds random bytes split at random sizes; `sanitize http` runs the tests under ASan and UBSan.

## Conformance and known limits

`tests/conformance/rfc9112_test.lua` holds the RFC 9112 and 9110 vectors, as data: request-line forms and the four request-target forms, malformed request and status lines, field syntax (OWS, empty values, case, obs-fold, characters), every rule of the message-framing table of RFC 9112 section 6.3 (Content-Length and Transfer-Encoding, requests and responses, HEAD, 1xx, 204, 304, CONNECT), chunked coding with extensions and trailers, connection persistence, upgrade, the examples quoted in the RFCs and the request-smuggling variants of section 11.2. Each message is fed whole and byte by byte, which must agree. A message the parser must refuse asserts the `ParseError` status (and `kind` where there is one) and that no head event is delivered.

Where llhttp 9.4.3 (strict mode) differs from the RFCs, the test asserts the behaviour as it is and the difference is listed here.

Stricter than the RFC (safe: the message is refused with 400; the RFC allows or recommends processing it):

- Several identical `Content-Length` values (`4, 4`, or two lines): RFC 9112 section 6.3 rule 5 lets a recipient merge them; llhttp refuses.
- `Content-Length` together with `Transfer-Encoding`: the RFC lets a server process the message with `Transfer-Encoding` and close the connection; llhttp refuses (RFC 9112 section 6.1, 11.2).
- A request whose last transfer coding is not `chunked`, or an unknown coding: the answer is 400, where RFC 9112 section 6.1 suggests 501 for a coding the server does not understand. The server may translate the case (`gzip` alone) into 501 once it inspects the field.
- Obsolete line folding in a response: RFC 9112 section 5.2 lets a client replace it with spaces; llhttp refuses it everywhere.
- Whitespace around the `;` and `=` of a chunk extension (`3 ; a = b`): RFC 9112 section 7.1.1 allows BWS; llhttp refuses.

More permissive than the RFC:

- A reason phrase may hold control characters other than CR and LF (NUL, ESC, DEL): RFC 9112 section 4 allows only HTAB, SP, VCHAR and obs-text. The reason is informational and nothing decides on it; a logger or a terminal must escape it. Recorded in `docs/open-questions.md` (OQ-67).
- Runs of SP in the request line (`GET  /  HTTP/1.1`) are accepted: RFC 9112 section 3 permits parsing on whitespace-delimited word boundaries. HTAB as a separator is refused.
- Any three-digit status code is delivered, `099` included (RFC 9112 section 4 asks for three digits; the defined range is RFC 9110 section 15). The caller validates with `hecate.http.Status`.
- After `Connection: close` the parser still parses a message that follows it in the same chunk: `keep_alive` is false on the head and the server must close without serving the next one (RFC 9112 section 9.6).

Found by the vectors and fixed in the binding: a request line without a version (`GET /`) was read by llhttp as HTTP/0.9 and delivered with the version `HTTP/0.9` (llhttp does not call its version callback for it); the head is now refused with kind `unsupported_version`. A front proxy that treats such a line as a request line and a back end that does not would disagree on where a message ends.

## Benchmark

`benchmarks/parse.lua` (`lua tools/run.lua bench http/parse`): messages per second for a small request (`GET /users/42`, 45 bytes), a browser-sized request (17 fields, cookies and a bearer token, about 0.9 KiB) and a response with 8 fields, fed whole and byte by byte, medians of 7 samples of 0.25 s. The parser is the full path: llhttp, the event records and the conversion to `Fields`. No threshold is set. Measured on a cloud VM (Intel Xeon 2.80 GHz, 4 vCPU, 16 GiB, Linux 6.18, Lua 5.5.1, one run, not pinned, noisy host), 2026-11-01:

| Message | Whole buffer | Byte by byte |
|---|---|---|
| request, small | 207 000 /s (8.9 MB/s) | 27 000 /s (1.2 MB/s) |
| request, browser-sized | 16 900 /s (14.9 MB/s) | 1 400 /s (1.3 MB/s) |
| response | 42 000 /s (13.3 MB/s) | 3 600 /s (1.1 MB/s) |

Byte by byte costs one native call per byte; a server feeds the bytes of one read at a time.

Pending: TLS in the server, the full limits suite, client, multipart and URL-encoded content.

## Layout (once implemented)

```text
src/hecate/http/init.lua   public entry point
tests/unit/  tests/conformance/  tests/integration/  tests/fixtures/
examples/    benchmarks/
csrc/        native sources
```
