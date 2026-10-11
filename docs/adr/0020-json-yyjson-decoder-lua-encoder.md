# 0020 — JSON: yyjson decoder, encoder in Lua

- **Status:** Proposed
- **Date:** 2026-10-11
- **Deciders:** project owner (agreed with the spike results in the pull request discussion; formal acceptance pending)
- **Packages:** json
- **Related:** [OQ-5](../open-questions.md), [spike report](../spikes/OQ-5-json-codec.md), ADR 0001

## Context

Decoding is where untrusted input and speed meet. The spike (Lua 5.5.1, Linux) measured
decode at 125 MB/s for a yyjson binding, 58 MB/s for lua-cjson and 12.7 MB/s for lunajson
(pure Lua). lua-cjson returns every number as a float and accepts NaN and invalid UTF-8;
yyjson and lunajson keep Lua integers exact; yyjson rejects all malformed cases tried.
Encoding: lunajson 14.5 MB/s, rxi json.lua 9.4, dkjson 8.8, lua-cjson (C) 98.9 MB/s.

## Options considered

1. **yyjson decoder + encoder in Lua** — fast strict decoding, no own C library. Consequences:
   encoding stays at pure-Lua speed (about 7 times slower than a C encoder).
2. **Own C codec for both directions** — fastest, no yyjson. Consequences: a C library to
   write, fuzz and secure; deferred by the owner as not a priority.
3. **lua-cjson** — rejected: no integer fidelity, not RFC 8259 strict.
4. **lunajson alone** — rejected as default: 10 times slower decoding.

## Decision

`hecate.json` decodes with a binding to yyjson (vendored, pinned) and encodes with Lua code
(starting from lunajson's design or an equivalent faster pure-Lua implementation chosen when
`json` is implemented, with the array/object/null markers of the package README). The
binding imposes a nesting limit (default 1000, configurable): the spike binding crashed on
a 5000-deep array without it. An own C codec remains a possible later optimisation.

## Consequences

- A C dependency (yyjson) and a binding to maintain, as for llhttp (ADR 0019).
- Encoding cost is visible in benchmarks of JSON responses; revisit with the
  `performance-engineer` when the `json` benchmark exists.

## Verification

Test corpus for RFC 8259 conformance, integer/float fidelity, depth limit and
invalid UTF-8; fuzzing of the binding (`fuzz` task); `native-code-reviewer` review.
