# Spike OQ-6: HTTP/1.1 parser (llhttp or Lua)

Status: **complete (Linux only)**. Recommendation submitted to the owner; the decision is
theirs.

## Method

- llhttp 9.4.3 (MIT), taken from the `release` branch of `nodejs/llhttp`, which carries the
  pre-generated C (`src/llhttp.c`, `src/api.c`, `src/http.c`): no Node.js toolchain is needed.
- A throwaway C binding (about 80 lines) parsing one request buffer into a Lua table,
  built with GCC `-O2` as a Lua 5.5.1 module together with the three llhttp C files.
- A throwaway pure-Lua parser (about 60 lines: request line, headers, Content-Length and
  chunked bodies, smuggling checks) as the "Lua parser" candidate.
- A 12-case corpus of valid and malformed requests, and a micro-benchmark: 11 runs of 100 000 parses
  of a 7-header GET, single thread, reporting the median.

Code lives in `spikes/OQ-6/` (git-ignored). Not yet run on macOS and Windows: the
llhttp sources are portable ANSI C with no platform code, but this is unverified until CI.

## Findings

| Case | llhttp | Lua parser |
|---|---|---|
| simple GET, POST with Content-Length, chunked POST | accept | accept |
| Content-Length with Transfer-Encoding (smuggling) | reject | reject |
| duplicate Content-Length | reject | reject |
| `+5` as Content-Length | reject | reject |
| space before colon, obsolete line folding, lowercase method | reject | reject |
| bare LF line endings | reject | reported as "incomplete" (the connection would wait) |
| NUL byte in a header value | reject | **accepted** |

Median of 11 runs of 100 000 parses each (mean, min and max in brackets):

| Parser | per request | requests/s |
|---|---|---|
| llhttp binding | 2.35 µs (mean 2.37, min 2.35, max 2.44) | 425 000 |
| pure Lua | 9.41 µs (mean 9.43, min 9.13, max 9.74) | 106 000 |

- The binding is about 4 times faster, and it already builds a Lua table, so the C
  parser cost itself is small. The Lua parser misses rejections that llhttp makes for
  free; each one (NUL, bare LF, invalid characters in values, request-target forms,
  trailers, upgrade, pipelining) would be a hand-written rule with its own tests, in a
  component exposed to untrusted input (request smuggling).
- llhttp is incremental (pauses, resumes across buffers), which the Lua prototype is not:
  it needs a whole buffer before it can parse. The Lua parser would need a streaming
  redesign, with a further cost.
- llhttp is MIT-licensed, is the parser of Node.js (heavily fuzzed and used) and the
  generated C is plain C99. Cost: one more vendored C library (ADR needed: new
  third-party dependency, owner gate) and a binding to maintain, including the memory
  rules for callbacks.
- Pitfall found while writing the binding: `luaL_Buffer` must not be interleaved, so the
  binding accumulates fields in C buffers and creates Lua strings once complete.

## Recommendation

Bind llhttp (the default assumption of OQ-6), vendoring the generated C from its
`release` branch, pinned by tag, with a small hand-written binding in `hecate.http`
that exposes an incremental parser object. Keep the Lua parser out of the request path.
Adding it still requires the owner's decision and an ADR (new dependency).

## Remaining risks

- macOS and Windows (MSVC) builds unverified; expected to be trivial.
- Vendoring policy for generated C (the release branch is not a source repository).
- Incremental binding with zero-copy fields is not prototyped; a hot-path benchmark is
  needed when `hecate.http` is built.
