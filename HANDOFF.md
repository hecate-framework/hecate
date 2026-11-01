<!-- Relay handoff note. Lives only on relay branches; deleted before review. -->
# Handoff

- roadmap_item: `http`: HTTP/1.1 server (llhttp, OQ-6) and client, message model, streaming, keep-alive, limits (Phase 2)
- status: in-progress
- lock_until: 2026-11-01T00:00:00Z
- last_update: 2026-11-01T15:45:09Z

## Done

- Step 1 (message model, pure Lua): `Fields`, `MediaType`, `Status`, `Request`, `Response`, `Cookie`/`SetCookie`, unit tests, README Public API and CHANGELOG.
- Step 2 (llhttp binding): llhttp 9.4.3 vendored, `csrc/native.c`, `hecate.http.parser` (feed, finish, skip_body, ParseError, limits), corpus tests, `build-native http`, CI steps for the three platforms. macOS and Windows builds are verified by CI only.
- Step 2b (native-code review of the binding) and step 2c: RFC 9112 conformance vectors (`tests/conformance/rfc9112_test.lua`), `benchmarks/parse.lua`, known limits in the README, OQ-67, fix of the HTTP/0.9 request line.
- Step 3c (TLS in the server): option `tls`, handshake in a forked computation per connection, `handshake_timeout`, `max_handshakes` (slot before `accept`: the excess waits in the backlog, decided and tested), `max_handshake_bytes` (`handshake_stream.lua`), logging with the peer address only (`logger` option), generic nothing-to-the-client on failure; tests `server_tls_test.lua`, `handshake_stream_test.lua`; CI plan output `net_native`. OQ-68 and OQ-69 updated with the owner's answers.
- Step 3d (owner defaults): `head_timeout`, `content_timeout`, `write_timeout` 60 s, `max_connections` unlimited by default, accept loop surviving `EMFILE` (backoff, one log per burst; tested with a flaky listener, a real descriptor limit cannot be set from Lua), invariant of `packages/http/CLAUDE.md` reworded, OQ-69 updated. Names decided afterwards: `request:read_content()`, `request:stream_content()`, `ContentStream` (OQ-68 resolved); `idle_timeout` 75 s.
- Step 4 (limits suite): whole-head deadline including a head after a pipelined request (`Parser:in_message()` in `native.c`, tested in `parser_test.lua`), `content_deadline` option, `tests/integration/server_limits_test.lua` with `tests/fixtures/client.lua`, README table "Limits and defaults", OQ-69 updated, OQ-70 (undetected disconnect during a handler: a restructuring, recommendation recorded). Benchmark `plaintext`: left to the Benchmarks roadmap item (no server scenario in `benchmarks/scenarios` yet).
- Step 5 (client): `client.lua`, `url.lua`, `Response:read_content/stream_content/close`, tests `client_test.lua`, `client_tls_test.lua`, `url_test.lua`; the server flushes the head of a streamed response at once; OQ-67 closed for the client; OQ-71 records the conservative choices.
- Step 6 (forms): `form.lua`, `multipart.lua`, `request:read_form()`, `request:stream_parts()`, client `form` and `multipart`, tests `form_test.lua`, `multipart_test.lua`, `multipart_property_test.lua`, `server_forms_test.lua`, benchmark `benchmarks/forms.lua`, OQ-72. The five deferred findings of the roadmap item are delivered; their evidence is in the table "Delivery of the rows deferred to `http`" at the end of `docs/reviews/phase-1.md`.
- Step 7a (security review fixes): M1 `%2B`, M2 bare CRLF counts as a pending head, M3 `content_deadline` 300 s, `drain_timeout` 5 s, client `timeout` 300 s, M4 `max_idle_connections` with a sweep, M5 cross-origin 307 and 308 not replayed, `strip_on_redirect`, L1 to L7 and L9 and L10 as listed in the CHANGELOG; documented: L8 (OQ-69), the SSRF paragraph (OQ-74), CSPRNG (OQ-73). Names unchanged: a second batch renames `handler` to `action`, `content_deadline` to `request_timeout` and kind and reason.
- Tooling: `setup-luals` task; `typecheck` falls back to `spikes/luals`; the relay documents require `typecheck` before every push.
- Step 3, first part (commit ac17a94): `http.Server(handler, options)` with `serve(listener)` and `shutdown()`: keep-alive, pipelining, 100-continue, HEAD, chunked responses, Host check, 413, generic 500, graceful shutdown; `tests/integration/server_test.lua`.
- Step 3b (this run, on top of ac17a94, API kept: `Server(handler, options)`): streaming request content (`content.lua`), problem details (`problem.lua`), response framing (`wire.lua`), deadlines, `max_connections`, numeric loopback `listen`, 501 for upgrades, `Parser:close()` and 16 KiB chunks, tests in `server_lifecycle_test.lua` and unit tests. Root causes found: the event queue of a connection used `#queue` after consuming entries (a second request on a connection never started); a response was sent without `Connection: close` when the handler ignored an `Expect: 100-continue` content; a content writer that failed left its head unflushed.

Cloud image note: run the tests with `LUA_CPATH="/opt/lua-5.5/lib/lua/5.5/?.so;;"` so that `luv` is found, and `lua tools/run.lua build-native json` first (`hecate.http.problem` encodes JSON).

## Next steps

1. Left from step 2: the first CI run on macOS and Windows (build, `sanitize http` in `native.yml`, `fuzz parse` for a minute; clang's libFuzzer runtime is absent in the cloud image).
2. Step 3b is done (see Done). Review it with `/review-package` at the end of the item: `request.content` is no longer filled by the server (OQ-68, resolved).
3. Step 3c is done (see Done).
4. Step 4 is done (see Done).
5. Step 5 is done (see Done).
6. Step 6 is done (see Done).
7. Step 7: docs in `website/`, examples, benchmarks, `typecheck`, `/review-package`, then Finish.

## Decisions taken (and where they are recorded)

Server defaults (step 3d): see OQ-69; step 4 must judge them and decide between-reads versus whole-message deadlines.

Server (step 3b): the handler failure, transport failure and parser failure texts are fixed (`problem.lua`); a connection serves its requests sequentially (pipelining without concurrency); an `Upgrade` request gets 501 until `websocket` exists; `shutdown` takes a grace period and then cancels. Choices recorded as OQ-68 and OQ-69.

Conservative choices inside the message model (no ADR needed): malformed media types and cookies return nil or are skipped instead of raising; `Fields:combined` refuses `Set-Cookie` (RFC 9110 section 5.3); `Response` refuses content on 1xx, 204, 304; `SetCookie` refuses `SameSite=None` without `Secure`.

## Doubts and questions for the owner

- OQ-69 (numeric `host` only, first values of the defaults), both in `docs/open-questions.md`.

## Commands to re-run

```sh
lua tools/run.lua test http
```
