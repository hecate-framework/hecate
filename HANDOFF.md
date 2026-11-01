<!-- Relay handoff note. Lives only on relay branches; deleted before review. -->
# Handoff

- roadmap_item: `http`: HTTP/1.1 server (llhttp, OQ-6) and client, message model, streaming, keep-alive, limits (Phase 2)
- status: in-progress
- lock_until: 2026-11-01T00:00:00Z
- last_update: 2026-11-01T13:00:00Z

## Done

- Lock released at the owner's request (the next run starts at 14:30 Paris). CI was green; typecheck fixed in 6d17b80.
- `setup-luals` task added; `typecheck` falls back to `spikes/luals`; relay doc and template require `typecheck` before every push.

- Claimed the item after the Phase 1 gate merge (PR #47).
- Step 1 (message model, pure Lua): `Fields`, `MediaType`, `Status`, `Request`, `Response`, `Cookie`/`SetCookie` in `packages/http/src/hecate/http/`, unit tests in `packages/http/tests/unit/`, README Public API and CHANGELOG. `test http`, `lint`, `check-package-structure`, `check-boundaries`, `check-glossary`, `check-rockspecs`, `check-changelog`, `check-lua-constructs`, `check-annotations` pass. `typecheck` not run (LuaLS not installed).

- Step 2 (llhttp binding, pure of server): llhttp 9.4.3 vendored (`csrc/vendor/`, VENDORED.md, THIRD_PARTY_NOTICES section 5), `csrc/native.c`, `hecate.http.parser` (feed/finish/skip_body, ParseError, limits), corpus tests first in `tests/unit/parser_test.lua`, `build-native http` and CI steps (POSIX and Windows, `http_native` plan output). `test http`, `lint`, `typecheck`, `check-licenses`, `check-boundaries`, `check-package-structure`, `check-rockspecs`, `check-changelog`, `check-glossary`, `check-lua-constructs`, `check-annotations`, `sanitize http` pass locally. macOS and Windows builds are verified by CI only.

## Next steps

1. Step 2b is done (native-code review of e59793e fixed, see CHANGELOG). Left: RFC 9112 test vectors, a parse benchmark in `benchmarks/`, and the first CI run on macOS and Windows (build, `sanitize http` in `native.yml`, `fuzz parse` for a minute; clang's libFuzzer runtime is absent in the cloud image, so the target was checked locally with an ASan/UBSan driver over 180k mutated inputs only).
2. Step 3: server over `hecate.net` (keep-alive, pipelining, `Expect: 100-continue`, chunked, HEAD without content, one coroutine and scope per request, graceful shutdown).
3. (also for step 3) the server answers 400 to an HTTP/1.1 request without exactly one `Host` field (review finding 3, deferred: the parser exposes the fields); it calls `Parser:close()` when a connection ends and feeds chunks no larger than its read buffer (review finding 9). Both are in the roadmap `http` item.
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
