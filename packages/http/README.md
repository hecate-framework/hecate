# `hecate-http`

> HTTP/1.1 server and client with a message model following RFC 9110 semantics.

| | |
|---|---|
| Module | `hecate.http` |
| Rock | `hecate-http` |
| Layer | 2 — Protocol |
| Roadmap phase | 2 |
| Status | alpha — implemented in Phase 2: message model, parser, server, client, forms and multipart; documentation and review done in PR 52 |
| Lua | 5.5 (`lua >= 5.5, < 5.6`) |
| Depends on | [`core`](../core), [`reactor`](../reactor), [`net`](../net), [`json`](../json), [`log`](../log) (the `logger` option is any `hecate.log.Logger`, used through `logger:log`; `log.default()` when none is given) |
| Used by | `hecate`, `kernel`, `websocket`, `test`, `cli` |
| Native code | llhttp binding (ADR 0019) |
| Specification | [http-and-routing.md](../../docs/architecture/http-and-routing.md) |
| Decisions | [ADR 0003](../../docs/adr/0003-transparent-structured-concurrency.md), [0018](../../docs/adr/0018-error-signalling.md), [0019](../../docs/adr/0019-http-parser-llhttp.md), [0023](../../docs/adr/0023-multi-process-serving.md), [0024](../../docs/adr/0024-tls-trust-store.md), [0025](../../docs/adr/0025-ambient-context.md); open questions OQ-67 to OQ-82 in [open-questions.md](../../docs/open-questions.md) |
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

Message model:

- `http.Fields`: case-insensitive, multi-valued, order-preserving fields (`add`, `set`, `get`, `get_all`, `combined`, `has`, `remove`, `count`, `lines`, `copy`); refuses CR, LF and NUL in values and non-token names.
- `http.MediaType`: `MediaType.parse` (nil and a reason on malformed input), `format`, `essence`, `suffix`, `matches`.
- `http.Status`: `reason`, `class`, `is_valid`, `forbids_content`.
- `http.Request`: `method`, `target`, `path`, `query`, `fields`, `content`, `parameters`, `scope`; `content` is nil for a request built by the server (the content is read with `read_content` or `stream_content`), the string given to `http.Request({ content = ... })` for a request built by hand (any other type is an `ArgumentError`), and the validated value once the kernel has validated the content; `peer_address()`, `cookies()`, `media_type()`, `set_validated_content(value)` (called by the kernel after it validated the content: `content` holds the value and `stream_content`, `read_content`, `read_form` and `stream_parts` raise `ContentError` with reason `consumed`).
- `http.Response`: `status`, `reason`, `fields`, `content`; `set_cookie`, `is_successful`.
- `http.Cookie.parse` (the `Cookie` field, RFC 6265 section 4.2.1) and `http.SetCookie` (`format`).

Implemented (server, needs the native module): `http.Server(action, options)`, `server:listen()` (*suspends*, returns the listener), `server:serve(listener?)` (*suspends*; a second `serve` while serving raises `core.StateError`), `server:shutdown(grace_timeout?)` (*suspends*), `server:local_address()`, `Server.DEFAULTS`; `http.serve_request(action, request)` (*may suspend*, needs no socket and no native module; named by the owner, OQ-78) runs an action as the server does and returns the response to send and the failure it caught (nil when none; the caller logs it); it holds the `pcall` around the action, the validation of the result (a `Response` with a valid status, reason and fields, final status, content nil, a string or a function) and the mapping to problem details, and raises a cancellation again; the `on_request_end(request)` server option: called once for each request given to the action, when its serving has ended (response sent, a writer included, or failed, or the request cancelled), every computation of the request having completed; it runs in the connection's computation, which may be cancelled, so a cleanup that suspends uses `reactor.shield`; an error is discarded and reported to `on_error`; `hecate.kernel` ends the service scope of a request with it. `on_response(info)` server option (OQ-81: method, target, status, bytes, duration, failed, refused; called after every response, errors discarded); also `http.ContentStream`, `http.ContentError` and `http.problem`.

- One coroutine per connection, and per request one scope (`request.scope`) with one coroutine running the action; a connection serves its requests in order, so pipelined responses come in request order; keep-alive and `Connection: close` (HTTP/1.0 closes unless it asks to keep alive); `Date` field; `Expect: 100-continue` (sent when the action first reads the content; any other expectation: 417; an action that never reads closes the connection after its answer); 400 for an HTTP/1.1 request without exactly one `Host` and for any request with several `Host` lines; 400 for a target with a fragment (`#`) and for the asterisk-form (`*`) outside OPTIONS (RFC 9112 section 3.2); the parser's `context.status` (400, 414, 431); 501 for an `Upgrade` or `CONNECT` request; the parser is fed chunks of at most 16 KiB and closed when the connection ends.
- Logging (OQ-79): the server logs through the `logger` option, or through `log.default()` (a console logger on standard error at `informational`) when none is given; an explicit `logger` replaces it. It logs an unhandled error of an action at `error` severity (fields `method`, `path`, `error`; the client still gets the generic problem details), the listening address, failed TLS handshakes and accept failures. `on_error` is unchanged. Tests pass their own `Logger` with a `MemorySink`.
- The response writer is split in a pure normalisation of the frame and the fields (lengths, HEAD, 204, 205, `Connection`, `Date`; internal `normalise`) and the writing.
- Errors are RFC 9457 problem details (`application/problem+json`, `type` `about:blank`) with a fixed `detail` chosen by status or by the class of the failure: an action failure, a transport or network failure (`reactor.TransportError`: never an address, an errno or `context.attempts`), a parser failure. The text of an error never reaches the client; `on_error(err)` receives it.
- Request content is a stream: `request:stream_content()` (a `ContentStream`: `read()` chunk by chunk, `read_all(limit?)`, `is_finished()`) and `request:read_content(limit?)` (the whole content). It is read when the action asks; what the action leaves unread is drained (up to `max_content`) so the next request can be parsed. Over `max_content` it is a 413 (`ContentError`; with a `Content-Length` over the limit the action does not run).
- Response content is nil, a string (`Content-Length`) or a function `content(write, flush)` that streams (`http` is bytes only and never serialises, OQ-76 a: the `Response` constructor raises `ArgumentError` for any other type, and a table set on a hand-made object is the generic 500 problem details response and a log entry): chunked coding, or the raw bytes when the action declared a `Content-Length`, or close-delimited for HTTP/1.0. HEAD, 1xx, 204, 205 and 304 never carry content (205 goes out with `Content-Length: 0`, RFC 9110 section 15.3.6; the `Response` constructor refuses content for it); the framing fields of the action (`Content-Length`, `Transfer-Encoding`, `Connection`) are replaced by the server's own.
- `listen` binds a NUMERIC address: the option `host` defaults to `127.0.0.1` (loopback only) and a name is an `ArgumentError`; every interface is `0.0.0.0` or `::` (OQ-69).
- Defaults (`Server.DEFAULTS`, each one an option), one per line:
  - `max_content`: 1048576 bytes; over it, a 413.
  - `head_timeout`: 60 s, counted from the first byte of a head to the end of the head, not between reads; then a 408.
  - `idle_timeout`: 75 s (nginx's value), between requests; the connection closes silently.
  - `content_timeout`: 60 s, between two reads of content (not a limit on the whole content); then a 408.
  - `request_timeout`: 300 s, from the end of the head to the last byte of content; then a 408.
  - `write_timeout`: 60 s for one write to the client; then the connection closes.
  - `drain_timeout`: 5 s for the unread content after a response.
  - `backlog` 128, `port` 8080, `host` `127.0.0.1`; parser limits as listed below (`parser` option).
  - `max_connections`: no limit (an integer limits, and the others wait in the backlog). The resource is bounded by the descriptor limit of the process, `idle_timeout` and `head_timeout`. An internet-facing server sets it (about 80% of the descriptor limit, for instance 50000 with `ulimit -n 65536`, less behind a proxy that already caps connections), sets a descriptor limit (`ulimit -n`, systemd `LimitNOFILE`) and runs behind a reverse proxy that caps connections, with an upstream keep-alive timeout below `idle_timeout`.
- The accept loop survives descriptor exhaustion (`EMFILE`, `ENFILE`) and any other accept failure: connections in service keep being served, the loop backs off (50 ms doubling to 1 s) instead of spinning, resumes by itself, and the burst is reported once (the logger and `on_error`).
- `shutdown(grace_timeout)` (a duration in seconds, default 30) stops accepting, closes the idle connections (those that served a request and wait for the next with no byte of its head yet), lets each request in flight finish (`Connection: close`), then returns; a connection whose request head has partly arrived (first or next request) is in flight, not idle: its request is served with `Connection: close`, its head still bounded by `head_timeout` and the grace period; a fresh connection (no byte of its first request head yet, for instance one handed over just before the stop) is not closed at once: it has 1 second (a constant, `connection.FRESH_GRACE`, or the `grace_timeout` when shorter; `head_timeout` is too long for a silent client) to start its request, which is then served with `Connection: close`, and is closed when none starts; when the grace period expires the remaining requests are cancelled. `serve` returns once every connection has ended.
- TLS (option `tls`: the options of `net.tls.server_config`, ALPN defaulting to `http/1.1`, or a configuration it built; needs the TLS native module of `net`): each accepted connection handshakes in its own computation, never in the accept loop, so a silent client holds nothing but its own slot. Bounds, each an option with a safe default in `Server.DEFAULTS`: `handshake_timeout` 10 s (the connection is dropped), `max_handshakes` 64 (a handshake slot is taken before `accept`, so the excess waits in the kernel backlog; a silent client can hold a slot until its deadline), `max_handshake_bytes` 65536 (bytes read from a client before the handshake ends; over it the connection is dropped). A failed handshake sends the client nothing of its own; the logger receives `http.Server: TLS handshake failed` with the peer address and the reason class, and nothing else leaves the server. `shutdown` drops connections still in their handshake. These options need `tls`.
- `request.path` and `request.query` are raw: as received, not percent-decoded and not normalised (dot segments stay). `server:is_stopping()` is public (a kernel can refuse new work while the server drains). There is no `Server:close()`: stopping suspends, because it waits for the requests in flight, and a `<close>` scope cannot suspend, so `shutdown` is the only stop. `serve` takes any net listener whose `accept` returns a stream with `reader`, `writer`, `shutdown` and `close`; only a `TcpListener` is tested. `Server.DEFAULTS` and `Client.DEFAULTS` are typed (`hecate.http.ServerDefaults`, `hecate.http.ClientDefaults`); a setting with no entry has no default value (`max_connections`: no limit).
- Known limits of the server: a client that disconnects while its action runs is not detected (nothing reads the connection then; the action runs to its end and the write fails; OQ-70); a connection serves its requests one at a time, so there is no concurrency within a connection.

### Limits and defaults

Every limit is an option of `http.Server` (the parser limits go in its `parser` table). `Server.DEFAULTS` holds the values the server itself applies. Each row is exercised by `tests/integration/server_limits_test.lua`, which also checks that the server answers a new connection afterwards and leaks no handle. The answer to a limit that is exceeded is RFC 9457 problem details (`application/problem+json`, fixed `detail`) and the connection closes, except where the cell says otherwise.

| Limit | Option | Default | When exceeded | Enforced by |
|---|---|---|---|---|
| Request target | `parser.max_target_size` | 8192 bytes | 414 | parser |
| One field name or value, reason phrase | `parser.max_field_size` | 8192 bytes | 431 | parser |
| Fields in a head or trailer section | `parser.max_fields` | 100 | 431 | parser |
| Raw bytes of a head, trailer section or chunk framing | `parser.max_head_size` | 65536 bytes | 431 | parser |
| Request content | `max_content` | 1048576 bytes | 413 (before the action when `Content-Length` says so, else at the read) | server |
| Head, first byte to its end (whole-head deadline: bytes that keep arriving do not extend it; a head after a pipelined request is timed from the moment the server turns to it) | `head_timeout` | 60 s | 408 | server |
| Wait for the next request | `idle_timeout` | 75 s | closed without an answer | server |
| Between two reads of content | `content_timeout` | 60 s | 408 | server |
| Head end to last byte of content (bounds a client that trickles within `content_timeout`) | `request_timeout` | 300 s | 408 | server |
| Draining content the action left unread, after the response | `drain_timeout` | 5 s | the connection closes | server |
| One write to the client (a reader that never reads a large response) | `write_timeout` | 60 s | connection closed, the writing action gets a `DeadlineExceededError` | server |
| Connections served at once | `max_connections` | none (bounded by the process descriptor limit, `idle_timeout` and `head_timeout`) | the excess waits in the backlog | server |
| TLS handshakes at once | `max_handshakes` | 64 | the excess waits in the backlog | server |
| TLS handshake time | `handshake_timeout` | 10 s | dropped, nothing sent | server |
| Bytes read during a TLS handshake | `max_handshake_bytes` | 65536 | dropped, nothing sent | server |
| Pairs in a urlencoded form | `read_form` `max_pairs` | 1000 | 413 | form |
| Size of a urlencoded form | `read_form` `max_size` | 1048576 bytes | 413 | form |
| Parts in a multipart message | `stream_parts` `max_parts` | 100 | 413 | form |
| Header fields of a part | `stream_parts` `max_part_fields_size` | 8192 bytes | 413 | form |
| Content of one part | `stream_parts` `max_part_size` | 1048576 bytes | 413 | form |
| A whole multipart message | `stream_parts` `max_total_size` | 1048576 bytes (the server `max_content` applies first) | 413 | form |
| Pipelined requests | none (see below) | what one 16 KiB read holds | back-pressure | server |

`head_timeout` is a deadline on the whole head, which is what defends against a client that sends a byte per interval (slowloris); `content_timeout` is a timeout between reads, as in nginx and Apache, so a slow but steady upload is not cut (`request_timeout`, 300 s by default, bounds its total time; raise it for uploads that legitimately last longer). Pipelining is bounded without an option: the server reads at most 16 KiB at a time, only when it has answered every request already parsed, so a client that pipelines more waits in the kernel buffers instead of in the server's memory.

Further behaviour of the server, from the security review:

- Bytes that begin no message (bare CRLF before a head, which llhttp skips) count as a pending head: a client that sends only line breaks is held to `head_timeout`, and the leading empty lines count in `parser.max_head_size`.
- The `Host` field must be one `uri-host [ ":" port ]` (a registered name of unreserved characters, an IPv4 address or a bracketed IPv6 literal, at most five digits of port): a list, a path, userinfo or a blank is a 400. An absolute-form target (`GET http://host/path`) is accepted only when its authority equals `Host` (case-insensitively; no userinfo, no fragment), and `request.path` and `request.query` are then those after the authority; any mismatch is a 400.
- A action's response is validated before it is sent: a status outside 100 to 599 (or an interim one), `fields` that are not a `Fields`, a `reason` that is not a string or content of another type is a 500 with generic problem details, reported to `on_error`.
- Known limits, by design for now: there is no per-request action timeout (an action that never returns holds its connection; bound it with `reactor.deadline` inside the action or in the kernel), no limit on the requests of one connection, and `Transfer-Encoding: gzip, chunked` is accepted as chunked: the action sees the compressed bytes (no decompression). A native call that makes no progress is a terminal `ParseError` of reason `no_progress` (status 500).

Deployment notes: Hecate serves HTTP itself and can face clients directly; a reverse proxy is optional, and the limits stay in force behind one.

Implemented (client, needs the native module): `http.Client(options?)`, `client:request(method, url, options?)` (*suspends*), the thin wrappers `get`, `head`, `delete`, `options` (`client:get(url, options?)`) and `post`, `put`, `patch` (`client:post(url, content?, options?)`), `client:close()`, `Client.DEFAULTS`; `http.url` (`parse`, `resolve`); on a `Response`: `read_content(limit?)` (*suspends*), `stream_content()` and `close()`.

- A request returns once the response head has arrived. The content is read lazily, through `response:read_content(limit?)` (bounded by `max_content`, 10 MiB) or `response:stream_content()` (a `ContentStream`, chunk by chunk, nothing is buffered beyond one read). A response with unread content holds its connection (and its slot in the pool) until the content is read to its end or `response:close()` drops the connection; a failure while reading drops it too. Responses to HEAD and 204, 304 or a zero length give their connection back at once.
- Request content: a string (sent with `Content-Length`), a function `content(write)` (streamed, chunked, never replayed) or a table (JSON). `Host` comes from the URL (default ports omitted, IPv6 literals bracketed) whatever the caller's fields say; `Content-Length` and `Transfer-Encoding` are the client's own; field values with CR, LF or NUL and invalid names are refused (`Fields`); a URL must be absolute `http` or `https` without userinfo, whitespace, control or non-ASCII characters (`ArgumentError`). Targets are sent in origin-form. `expect_continue = true` sends `Expect: 100-continue` and waits `expect_timeout` (1 s) for the interim response before the content (default off); a final answer instead of `100` is returned without the content being sent.
- Pool, per origin (scheme, host, port): at most `max_connections_per_origin` (8) connections in use or idle, the next request waits; idle connections are reused newest first and expire after `idle_timeout` (30 s, shorter than the 75 s of the server) and when the peer closed them (a check on reuse); a reused connection that turns out dead before any byte of the response arrived is retried once on a new one, for idempotent methods (GET, HEAD, PUT, DELETE, OPTIONS, TRACE) with replayable content only; a POST is never repeated. `close()` closes the idle connections and refuses further requests (`core.StateError`); connections in use are closed when their response ends.
- Pool size: besides `max_connections_per_origin`, `max_idle_connections` (64) bounds the idle connections of the whole pool (the least recently used is closed first); expired and closed idle connections of every origin are swept at each checkout and checkin, and an origin without idle connection or lease is forgotten (`client:pool_stats()` gives `idle` and `origins`). A connection with bytes left after its response (the start of another message) is never pooled.
- Redirects (301, 302, 303, 307, 308 with a `Location`; `redirects = false` turns them off): at most `max_redirects` (10); 301 and 302 turn a POST into a GET and 303 turns anything but GET and HEAD into a GET (the content and its content fields are dropped); 307 and 308 repeat the request, and a streamed content is not replayable, so that response is returned as it is; `Authorization`, `Cookie`, `Proxy-Authorization`, `X-Api-Key`, `X-Auth-Token` and the names of the `strip_on_redirect` option are removed when the origin changes; a 307 or 308 that would send the content again to ANOTHER origin is not followed (the response is returned) unless `cross_origin_redirects = true` (client option or per request); an https to http redirect is refused (`allow_downgrade`); a loop and a chain beyond the cap are `ProtocolError`s (`context.reason`: `redirect_loop`, `too_many_redirects`, `downgrade`, `bad_location`); a relative `Location` is resolved (RFC 3986 section 5).
- Deadlines: `connect_timeout` 10 s (connect, and the TLS handshake), `head_timeout` 30 s (end of the request to the end of the head, a whole-head deadline), `content_timeout` 60 s (between two reads; a response content that stalls longer raises `http.ContentError` with `context.reason = "timeout"`, as the server does for a stalled request content, OQ-82), `write_timeout` 60 s, `request_timeout` (the whole exchange, redirects and content included; default 300 s so a trickling server cannot hold a response forever, per request through `options.request_timeout`; it is the one deadline of the content that stays a `core.DeadlineExceededError`; the server's `request_timeout` is the time from the end of a head to the last byte of its content). A cancelled request, or one that failed, drops its connection: no reuse after an unknown state.
- TLS: the system trust store by default (ADR 0024), `tls = { ca_pem, system_roots, cert_pem, key_pem }` to add an anchor or present a client certificate; ALPN `http/1.1`; verification cannot be turned off.
- Errors are core error objects: `reactor.TransportError` as `net` raises it (its message and `context.attempts` may list the addresses a name resolved to: the client does not hide them from its caller, so never forward them to a peer), `core.DeadlineExceededError` (`connect_timeout`, `head_timeout`, `write_timeout`, `request_timeout`), `net.EndOfStreamError` (the server closed before or inside the response), `net.TlsError`, `http.ParseError` (a malformed response or a `parser` limit: 431 and its kind), `http.ContentError` (`context.reason` `too_large` over `max_content`, with `context.limit`, or `timeout` past `content_timeout`; it carries no `context.status`, which is the server's to give, OQ-82; `http.problem` maps it to a 500 when it escapes an action), `core.StateError` (a request on a closed client) and `core.ProtocolError` (see redirects; `reason_phrase` for a reason phrase with control characters, OQ-67, which the client refuses; `status`, `upgrade`). A 101 or an upgrade is refused.
- Per request, `client:request` (and the wrappers) take `fields`, `content`, `form`, `multipart`, `redirects`, `expect_continue`, `cross_origin_redirects`, `request_timeout`, `head_timeout`, `content_timeout`, `max_content` and `max_redirects`; any other key is an `ArgumentError` (TLS is per client). `max_content` bounds `read_content`, `read_json` and `stream_content` alike. The `tls` option is a table of `net.tls.client_config` options or a configuration that function built.
- A response of the client also has `media_type()` (nil when absent or malformed) and `read_json(limit?)` (*suspends*; a `ProtocolError` with the reason `invalid_json` for content that is not JSON, the content never echoed). The constructor options `content_stream`, `discard` and `max_content` of `Response` are internal: do not use them.
- Not available: HTTP proxies, compression, a cookie jar, HTTP/2, `Retry-After` and built-in retries (only a request on a pooled connection that died is repeated once, see above), connection warm-up.

SSRF and redirects: the client does no address filtering. A caller that fetches URLs chosen by someone else (webhooks, link previews) must refuse private, loopback and link-local addresses itself, and a redirect can lead there: pass `redirects = false` and validate each `Location`, or resolve the name and filter the addresses before connecting. The client has no `connect` hook to do it for you (OQ-74); until then, do not give it a URL you did not choose without checking where it goes.

Implemented (forms, pure Lua, no native module needed): `http.form` (`parse_urlencoded(text, limits?)`, `encode_urlencoded(pairs)`, `DEFAULTS`), `http.Form` (`get`, `get_all`, `count`, `pairs`), `http.multipart` (`Reader`, `parts(source, media_type, limits?)`, `boundary_of(media_type)`, `basename(filename)`, `build(parts)`, `DEFAULTS`), `http.FormError`; on a request `request:read_form(limits?)` and `request:stream_parts(limits?)`; on the client the options `form` and `multipart`.

- urlencoded (WHATWG URL Standard 5.1): `&` separates pairs (empty ones are skipped), the first `=` splits name and value, `+` is a space, `%XX` a byte; names repeat and keep their order. Decisions, conservative: a malformed percent sequence (`%`, `%4`, `%zz`) is refused (the WHATWG parser keeps it literally; guessing is a smuggling aid), so are text that is not valid UTF-8 and a NUL byte; the limits are `max_pairs` (1000) and `max_size` (1048576 bytes). `encode_urlencoded` leaves `A-Z a-z 0-9 * - . _`, writes a space as `+` and the rest as `%XX`.
- multipart/form-data (RFC 7578, delimiters of RFC 2046 section 5.1): `request:stream_parts()` returns a `Reader`; `reader:next_part()` (*suspends*) gives the next `Part` or nil after the last one. A part has `name`, `filename`, `content_type`, `fields` (a `Fields`), `stream_content()`, `read_content(limit?)` (*suspends*) and `safe_filename()`. The reader pulls a chunk of the request content only when it needs one and keeps at most that chunk, the header fields of the part and the tail of a possible delimiter: a client that sends faster than the action reads waits in the kernel buffers. The delimiter is searched as CRLF, `--`, the boundary, then `--` or blanks and CRLF: bytes that look like a boundary but do not end that way are content, so a boundary in a file cannot split it unless it really is a delimiter. A part the action left unread is skipped within `max_part_size`.
- The filename is never trusted: `part.filename` is the raw value (a `filename*` of RFC 8187 in UTF-8 wins when it decodes; another charset is ignored), `multipart.basename` reduces it conservatively (directories, control characters, `< > : " | ? *`, leading dots, trailing dots and spaces, 255 bytes, Windows device names give nil) and is still not a licence to use a client's name: prefer a name you generate; no code of this package opens a file by a name a client sent. Names and filenames with NUL are refused; browsers write `"` and line breaks as `%22`, `%0D`, `%0A` and the parser leaves them (no decoding).
- Refused (`FormError`, `context.reason` and `context.status`): not `multipart/form-data` or a media type that does not parse (`unsupported_media_type`, 415); a boundary that is missing, over 70 characters or outside `0-9 A-Z a-z ' ( ) + _ , - . / : = ?` (the space is refused as well) (`bad_boundary`, 400); a part whose header fields are malformed, has a bare CR or LF, a NUL, an invalid name, a folded line or a `Content-Disposition` that is not `form-data` (`bad_part_fields`, 400); a part without a name (`missing_name`, 400); a message cut before its final boundary, bare line feeds instead of CRLF included (`truncated`, 400); over the limits (`too_many_parts`, `part_fields_too_large`, `total_too_large`, 413; a part over `max_part_size` is a `ContentError`, 413). The server answers with problem details that never echo the input.
- A nested `multipart/mixed` is not parsed: it is a part whose content is the inner message and whose `content_type` says so. `Content-Transfer-Encoding` is ignored (RFC 7578 section 4.7 deprecates it). A boundary immediately after the blank line that ends the header fields (`--boundary` CRLF) reads as the delimiter of an empty part, as RFC 2046 grammar does. Duplicate names are delivered in order.
- The client builds multipart messages (`multipart = { { name, filename?, content_type?, content } }`, `content` a string or a function that streams): the boundary is `hecate-` and 128 random bits (from `/dev/urandom` where it exists, else `math.random`: OQ-73), checked absent from the string parts; with only string parts the message is one string (a `Content-Length`, replayable), with a function part it is streamed chunked. `form = pairs` sends urlencoded content. `content`, `form` and `multipart` exclude each other.
- The parser is pure Lua, so it is not a libFuzzer target: `tests/unit/multipart_property_test.lua` is a deterministic property test (seeded generator) that parses valid and mutated messages whole, in random pieces and byte by byte, and requires the same outcome and only `ProtocolError` failures.

Implemented (parser, needs the native module: `lua tools/run.lua build-native http`; `http.Parser` or `require("hecate.http.parser")`; `require("hecate.http")` works without the module, then `Parser`, `Server` and `Client` are nil and `http.available()` returns `false` and the reason):

- `http.parser` (`Parser.request(options)`, `Parser.response(options)`): the incremental llhttp binding (ADR 0019; llhttp's lenient flags stay off and none is reachable). `feed(chunk)` returns the events (`head`, `data`, `complete` with optional trailers, `upgrade`) and a `ParseError` for malformed input or an exceeded limit; `finish()` for the end of the connection; `skip_content()` for the final response to HEAD (an interim 1xx does not consume it); `in_message()` tells whether a message has begun and not ended (the server times a pending head with it); `close()` releases the memory. Events before a failure are delivered only for messages that completed. A failed parser, and a parser after an upgrade, return the same error to every later call (`reason` `upgraded` after an upgrade). The `Fields` of a head or trailer section are built without checking again what llhttp refuses in strict mode (a name that is not a token, a control character other than HTAB or DEL in a value); a value with CR, LF or NUL is still refused (`invalid_field`, 400), and values are trimmed of SP and HTAB in time linear in their length.
- Accepted: HTTP/1.0 and HTTP/1.1 only; RTSP and ICE (their methods, protocols and versions) are refused, and so is the chunked transfer coding in HTTP/1.0.
- `ParseError` (a `core.ProtocolError`, `http.ParseError`): `context.reason` (the stable identifier: the binding's own refusals such as `target_too_long`, or llhttp's error code in lowercase without `HPE_`, such as `invalid_method`), `context.detail` (llhttp's text, informational), `context.code`, `context.position` (offset in the chunk of the failing call), `context.status` (400, 414 for the target, 431 for fields and heads).
- Limits with safe defaults, each an integer from 1 to 16777216 (an unknown option is an `ArgumentError`): `max_target_size` 8192, `max_field_size` 8192 (a name, a value, a reason phrase), `max_head_size` 65536 (raw bytes of a section: the head with its whitespace and leading empty lines, the bytes between two content chunks, the trailer section), `max_fields` 100, `max_events` 1024 (events recorded per native call; `feed` continues by itself). Feed chunks no larger than the read buffer: `feed` returns every event of the chunk in one list.
- Known llhttp behaviour kept as is: see "Conformance and known limits" below (a leading CRLF before a request line is ignored, RFC 9112 section 2.2).
- The third-party sources are vendored in `csrc/vendor/` (llhttp 9.4.3, MIT; `VENDORED.md`). A libFuzzer target (`fuzz parse`) feeds random bytes split at random sizes; `sanitize http` runs the tests under ASan and UBSan.

## Conformance and known limits

`tests/conformance/rfc9112_test.lua` holds the RFC 9112 and 9110 vectors, as data: request-line forms and the four request-target forms, malformed request and status lines, field syntax (OWS, empty values, case, obs-fold, characters), every rule of the message-framing table of RFC 9112 section 6.3 (Content-Length and Transfer-Encoding, requests and responses, HEAD, 1xx, 204, 304, CONNECT), chunked coding with extensions and trailers, connection persistence, upgrade, the examples quoted in the RFCs and the request-smuggling variants of section 11.2. Each message is fed whole and byte by byte, which must agree. A message the parser must refuse asserts the `ParseError` status (and `reason`) and that no head event is delivered.

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

Found by the vectors and fixed in the binding: a request line without a version (`GET /`) was read by llhttp as HTTP/0.9 and delivered with the version `HTTP/0.9` (llhttp does not call its version callback for it); the head is now refused with reason `unsupported_version`. A front proxy that treats such a line as a request line and a back end that does not would disagree on where a message ends.

## Benchmark

`benchmarks/parse.lua` (`lua tools/run.lua bench http/parse`): messages per second for a small request (`GET /users/42`, 45 bytes), a browser-sized request (17 fields, cookies and a bearer token, about 0.9 KiB) and a response with 8 fields, fed whole and byte by byte, medians of 7 samples of 0.25 s. The parser is the full path: llhttp, the event records and the conversion to `Fields`. No threshold is set. Measured on a cloud VM (Intel Xeon 2.80 GHz, 4 vCPU, 16 GiB, Linux 6.18, Lua 5.5.1, not pinned, noisy host), 2026-11-13, after the parser stopped re-validating the fields llhttp checks (review H-3: whole buffer, 19 700 /s before for the browser-sized request and 48 000 /s for the response, in runs interleaved with these):

| Message | Whole buffer | Byte by byte |
|---|---|---|
| request, small | 334 000 /s (15.0 MB/s) | 34 000 /s (1.5 MB/s) |
| request, browser-sized | 48 000 /s (42.3 MB/s) | 1 900 /s (1.7 MB/s) |
| response | 128 000 /s (40.2 MB/s) | 3 700 /s (1.2 MB/s) |

Byte by byte costs one native call per byte; a server feeds the bytes of one read at a time.

`benchmarks/forms.lua` (`lua tools/run.lua bench http/forms`): the form parsers, pure Lua, medians of 7 samples of 0.25 s, same machine and conditions (Lua 5.5.1, one run, 2026-11-01): urlencoded parse of 20 pairs (about 1 KiB with percent- and plus-encoded values) 6 500 /s (6.4 MB/s), encode 10 000 /s; multipart with 3 small parts (about 0.5 KiB) 11 600 /s whole (5.9 MB/s) and 1 500 /s byte by byte (0.8 MB/s); a 1 MiB file part fed in chunks of 16 KiB, 815 /s (815 MB/s: the delimiter search is a plain `string.find` and the content is cut, not scanned byte by byte). No threshold is set.

## Layout

```text
src/hecate/http/           the modules (init.lua is the entry point)
src/hecate/http/internal/  modules of the server and the client, not public API (options, response writer, connections, pool, exchange, redirects)
tests/unit/  tests/conformance/  tests/integration/  tests/fixtures/
examples/    benchmarks/
csrc/        the llhttp binding and its fuzz target
```
