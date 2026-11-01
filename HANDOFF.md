<!-- Relay handoff note. Lives only on relay branches; deleted before review. -->
# Handoff

- roadmap_item: `http`: HTTP/1.1 server (llhttp, OQ-6) and client, message model, streaming, keep-alive, limits (Phase 2)
- status: in-progress
- lock_until: 2026-11-01T17:15:09Z
- last_update: 2026-11-01T15:45:09Z

## Done

- Step 3 (server, first part): `hecate.http.server` (`Server`, `serve`, `shutdown`), `tests/integration/server_test.lua` (13 cases), README and CHANGELOG. Done: keep-alive, pipelining, 100-continue, HEAD, chunked responses, Host check, 413, generic 500, graceful shutdown. `test http`, `lint`, `typecheck`, `check-boundaries`, `check-glossary`, `check-annotations`, `check-lua-constructs`, `check-package-structure` pass locally (run with `LUA_CPATH="/opt/lua-5.5/lib/lua/5.5/?.so;;"` in the cloud image so `luv` is found).

- Step 2c: RFC conformance vectors (`packages/http/tests/conformance/rfc9112_test.lua`), `benchmarks/parse.lua` (numbers in the README), known limits in the README, OQ-67 (reason phrase control characters), fix of the HTTP/0.9 request line in `native.c` (test in `parser_test.lua`). Commands run: `test http`, `build-native http`, `bench http/parse`.
- Lock released at the owner's request (the next run starts at 14:30 Paris). CI was green; typecheck fixed in 6d17b80.
- `setup-luals` task added; `typecheck` falls back to `spikes/luals`; relay doc and template require `typecheck` before every push.

- Claimed the item after the Phase 1 gate merge (PR #47).
- Step 1 (message model, pure Lua): `Fields`, `MediaType`, `Status`, `Request`, `Response`, `Cookie`/`SetCookie` in `packages/http/src/hecate/http/`, unit tests in `packages/http/tests/unit/`, README Public API and CHANGELOG. `test http`, `lint`, `check-package-structure`, `check-boundaries`, `check-glossary`, `check-rockspecs`, `check-changelog`, `check-lua-constructs`, `check-annotations` pass. `typecheck` not run (LuaLS not installed).

- Step 2 (llhttp binding, pure of server): llhttp 9.4.3 vendored (`csrc/vendor/`, VENDORED.md, THIRD_PARTY_NOTICES section 5), `csrc/native.c`, `hecate.http.parser` (feed/finish/skip_body, ParseError, limits), corpus tests first in `tests/unit/parser_test.lua`, `build-native http` and CI steps (POSIX and Windows, `http_native` plan output). `test http`, `lint`, `typecheck`, `check-licenses`, `check-boundaries`, `check-package-structure`, `check-rockspecs`, `check-changelog`, `check-glossary`, `check-lua-constructs`, `check-annotations`, `sanitize http` pass locally. macOS and Windows builds are verified by CI only.

## Next steps

1. Steps 2b and 2c are done. Left: the first CI run on macOS and Windows (build, `sanitize http` in `native.yml`, `fuzz parse` for a minute; clang's libFuzzer runtime is absent in the cloud image, so the target was checked locally with an ASan/UBSan driver over 180k mutated inputs only).
2. Step 3b: TLS in the server (finding 2 of the Phase 1 review: handshake limit, `tls.accept` in a forked computation, bounded bytes), numeric-address default for `listen` (finding 3), TransportError mapping (finding 1; the handler failure is already a generic 500). Review finding 9: the server reads chunks of 16 KiB, which is within the parser read buffer (check against `max_events`/buffer size in a test with a 16 KiB pipelined burst).
4. Step 4: limits with safe defaults (request line, field count and size, content size, read and idle deadlines; slowloris).
5. Step 5: client (pool per origin, redirects, deadlines, TLS, streaming).
6. Step 6: the three deferred Phase 1 findings (see docs/reviews/phase-1.md, rows deferred to `http`), multipart and URL-encoded content.
7. Step 7: docs in `website/`, examples, benchmarks, run `typecheck` (install pinned LuaLS under `spikes/`), `/review-package`, then Finish.

## Decisions taken (and where they are recorded)

Conservative choices inside the message model (no ADR needed): malformed media types and cookies return nil or are skipped instead of raising; `Fields:combined` refuses `Set-Cookie` (RFC 9110 section 5.3); `Response` refuses content on 1xx, 204, 304; `SetCookie` refuses `SameSite=None` without `Secure`.

## Doubts and questions for the owner

None yet.

## Commands to re-run

```sh
lua tools/run.lua test http
```
