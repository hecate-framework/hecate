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

- Step 2 (llhttp binding) BLOCKED, nothing implemented: the vendoring download was refused.
  Command: `curl -sS -L -o spikes/OQ-6/dl/llhttp.tgz https://github.com/nodejs/llhttp/archive/refs/tags/release/v9.4.3.tar.gz`
  Answer: HTTP 403 from the agent proxy, body "GitHub access to this repository is not enabled for this session. Use add_repo
  to request access." Needed: read access to `github.com/nodejs/llhttp` (host github.com, repository nodejs/llhttp; the
  `release` branch, tag v9.4.3 or the tag the spike pins) for the session. No workaround attempted (no npm or other mirror).
  `setup-luals` and `typecheck` pass on the unchanged tree.

## Next steps

0. Once access to nodejs/llhttp is granted: vendor `src/llhttp.c`, `src/api.c`, `src/http.c`, `include/llhttp.h`, LICENSE at the
   pinned tag into `packages/http/csrc/vendor/` with `VENDORED.md` (tag, commit sha, SHA-256 per file) and a THIRD_PARTY_NOTICES
   entry; add `http` to `c_modules` in `tools/tasks/build_native.lua` and to the CI `build-native` steps; write the
   malformed-request corpus tests first.
1. Step 2: llhttp binding (ADR 0019, spike OQ-6): `csrc/`, `build-native http`, parser wrapper, smuggling defences (conflicting Content-Length/Transfer-Encoding), fuzz target, RFC test vectors.
2. Step 3: server over `hecate.net` (keep-alive, pipelining, `Expect: 100-continue`, chunked, HEAD without content, one coroutine and scope per request, graceful shutdown).
3. Step 4: limits with safe defaults (request line, field count and size, content size, read and idle deadlines; slowloris).
4. Step 5: client (pool per origin, redirects, deadlines, TLS, streaming).
5. Step 6: the three deferred Phase 1 findings (see docs/reviews/phase-1.md, rows deferred to `http`), multipart and URL-encoded content.
6. Step 7: docs in `website/`, examples, benchmarks, run `typecheck` (install pinned LuaLS under `spikes/`), `/review-package`, then Finish.

## Decisions taken (and where they are recorded)

Conservative choices inside the message model (no ADR needed): malformed media types and cookies return nil or are skipped instead of raising; `Fields:combined` refuses `Set-Cookie` (RFC 9110 section 5.3); `Response` refuses content on 1xx, 204, 304; `SetCookie` refuses `SameSite=None` without `Secure`.

## Doubts and questions for the owner

None yet.

## Commands to re-run

```sh
lua tools/run.lua test http
```
