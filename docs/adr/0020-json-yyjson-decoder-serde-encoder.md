# 0020 — JSON: yyjson decoder, serde_json encoder

- **Status:** Proposed
- **Date:** 2026-10-11
- **Deciders:** project owner (agreed with the spike results in the pull request discussion; formal acceptance pending)
- **Packages:** json
- **Related:** [ADR 0021](0021-rust-native-modules.md), [OQ-5](../open-questions.md), [spike report](../spikes/OQ-5-json-codec.md), ADR 0001

## Context

Decoding is where untrusted input and speed meet. The spike (Lua 5.5.1, Linux) measured
decode at 125 MB/s for a yyjson binding, 58 MB/s for lua-cjson and 12.7 MB/s for lunajson
(pure Lua). lua-cjson returns every number as a float and accepts NaN and invalid UTF-8;
yyjson and lunajson keep Lua integers exact; yyjson rejects all malformed cases tried.
Encoding: lunajson 14.5 MB/s, rxi json.lua 9.4, dkjson 8.8, lua-cjson (C) 98.9 MB/s.

## Options considered

1. **yyjson decoder + encoder in Lua** — Consequences: encoding at pure-Lua speed (15 MB/s).
2. **yyjson decoder + `serde_json` encoder through `mlua`** — 53 MB/s encoding, memory-safe
   code, no own C library. Consequences: needs the Rust build tool (ADR 0021).
3. **Own C codec for both directions** — fastest, no yyjson. Consequences: a C library to
   write, fuzz and secure; deferred by the owner as not a priority.
4. **lua-cjson** — rejected: no integer fidelity, not RFC 8259 strict.
5. **lunajson alone** — rejected as default: 10 times slower decoding.

## Decision

`hecate.json` decodes with a binding to yyjson (vendored, pinned) and encodes with
`serde_json` through `mlua` (ADR 0021), with the array/object/null markers of the package
README. The yyjson binding imposes a nesting limit (default 1000, configurable): the spike
binding crashed on a 5000-deep array without it. Since the encoder's speed is bounded by
`mlua`'s table access, improvements in `mlua` are inherited by upgrading it. An own C codec
remains a possible later optimisation, not a priority.

**One public API.** The two native libraries are an implementation detail of `hecate.json`:
users call a single `json.decode(text, options?)` / `json.encode(value, options?)` pair and
see one module, one set of options (nesting limit, markers), one error hierarchy
(`hecate.core` errors) and one value model (`null` marker, integer/float, array/object
markers). There is no codec object per backend and no backend name in the signatures. The
binding crates stay internal modules (for example `hecate.json.native`) that are not part of
the public API; a backend can be replaced (own C codec, a faster `mlua`) without any change
for callers. Both directions must agree on the value model: what `decode` returns, `encode`
accepts and reproduces (round-trip property tests).

## Consequences

- A C dependency (yyjson) and a binding to maintain, as for llhttp (ADR 0019).
- Encoding is about half the speed of a C encoder (lua-cjson, 99 MB/s); revisit with the
  `performance-engineer` when the `json` benchmark exists.
- Float formatting (`1.0` versus `1`) and empty-table markers are fixed in the `json`
  specification, not left to serde_json defaults.

## Verification

Round-trip property tests (`decode(encode(v)) == v`, which also pin the shared markers
between the two backends); test corpus for RFC 8259 conformance, integer/float fidelity, depth limit and
invalid UTF-8; fuzzing of the binding (`fuzz` task); `native-code-reviewer` review.
