# 0019 — HTTP/1.1 parsing with llhttp

- **Status:** Proposed
- **Date:** 2026-10-11
- **Deciders:** project owner (agreed with the spike recommendation in the pull request discussion; formal acceptance pending)
- **Packages:** http
- **Related:** [OQ-6](../open-questions.md), [spike report](../spikes/OQ-6-http-parser.md), [http-and-routing.md](../architecture/http-and-routing.md), ADR 0001

## Context

`hecate.http` parses untrusted input, so strictness (request smuggling) and speed matter.
The spike compared llhttp 9.4.3 (MIT) through a small C binding with a pure-Lua parser on
Lua 5.5.1: median 2.35 µs against 9.41 µs per request (about 4 times faster), and llhttp
rejected malformed inputs (NUL in header values, bare LF) that the Lua parser accepted or
stalled on. llhttp is incremental, which a streaming server needs.

## Options considered

1. **llhttp through a binding** — MIT, heavily used (Node.js), incremental. Consequences:
   one more vendored C library and a binding to maintain.
2. **Parser written in Lua** — no native dependency. Consequences: 4 times slower on the
   request path, every strictness rule hand-written and tested, streaming to be designed.

## Decision

`hecate.http` binds llhttp. The generated C sources are vendored from the `release`
branch of `nodejs/llhttp`, pinned by tag. The binding exposes an incremental parser
object; no Lua parser is kept in the request path.

## Consequences

- A third-party C dependency is added (owner-approved with this decision), recorded in the
  `check-licenses` inventory.
- The binding follows the native-code review rules (memory ownership of callback data).
- The 3-platform build of the binding is verified in CI when `hecate.http` is created.

## Verification

`check-licenses`; the `hecate.http` test suite includes a malformed-request corpus
(smuggling, NUL, bare LF, duplicate lengths); `native-code-reviewer` review.
