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
- Tooling: `setup-luals` task; `typecheck` falls back to `spikes/luals`; the relay documents require `typecheck` before every push.
- Step 3, first part (commit ac17a94): `http.Server(handler, options)` with `serve(listener)` and `shutdown()`: keep-alive, pipelining, 100-continue, HEAD, chunked responses, Host check, 413, generic 500, graceful shutdown; `tests/integration/server_test.lua`. A second, unpushed version written in parallel by another session was merged into this base (see Next steps, step 3b).

Cloud image note: run the tests with `LUA_CPATH="/opt/lua-5.5/lib/lua/5.5/?.so;;"` so that `luv` is found, and `lua tools/run.lua build-native json` first (`hecate.http.problem` encodes JSON).

## Next steps

1. Left from step 2: the first CI run on macOS and Windows (build, `sanitize http` in `native.yml`, `fuzz parse` for a minute; clang's libFuzzer runtime is absent in the cloud image).
2. Step 3b (in progress): port onto the `Server(handler, options)` API the streaming content reader, the deadlines (head, idle, content, write), `max_connections`, the numeric loopback default of `listen` (finding 3), problem details with the `TransportError` mapping (finding 1), `Parser:close()` and the 16 KiB burst test (finding 9), `Upgrade` and `CONNECT` answered with 501.
3. Step 3c: TLS in the server (finding 2 of the Phase 1 review: handshake limit, `tls.accept` in a forked computation, bounded bytes).
4. Step 4: the full limits suite (slowloris, request line, field count and size, per-connection budgets).
5. Step 5: client (pool per origin, redirects, deadlines, TLS, streaming).
6. Step 6: the remaining deferred Phase 1 findings (see docs/reviews/phase-1.md), multipart and URL-encoded content.
7. Step 7: docs in `website/`, examples, benchmarks, `typecheck`, `/review-package`, then Finish.

## Decisions taken (and where they are recorded)

Conservative choices inside the message model (no ADR needed): malformed media types and cookies return nil or are skipped instead of raising; `Fields:combined` refuses `Set-Cookie` (RFC 9110 section 5.3); `Response` refuses content on 1xx, 204, 304; `SetCookie` refuses `SameSite=None` without `Secure`.

## Doubts and questions for the owner

None yet.

## Commands to re-run

```sh
lua tools/run.lua test http
```
