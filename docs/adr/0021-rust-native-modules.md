# 0021 — Rust as a build-time tool for native modules (TLS, JSON encoding)

- **Status:** Accepted
- **Date:** 2026-10-11
- **Deciders:** project owner (accepted by the project owner, 2026-10-11)
- **Packages:** net, json (and the bootstrap, CI and release tooling)
- **Related:** [OQ-4](../open-questions.md), [OQ-5](../open-questions.md), [TLS spike](../spikes/OQ-4-tls.md), [JSON spike](../spikes/OQ-5-json-codec.md), ADR 0001, ADR 0020, ADR 0017

## Context

`hecate.net` needs TLS and `hecate.json` needs an encoder faster than pure Lua. Writing the
protocol and memory-management code in C was judged too costly and risky. The spikes showed,
on Lua 5.5.1 and Linux:

- `mlua` 0.12.2 (MIT) supports Lua 5.5 (`lua55` feature) and builds a loadable module.
- `rustls` 0.23 (sans-IO, memory safe) completed an in-memory TLS 1.3 handshake and data
  round trip from Lua (about 0.5 ms per handshake in process); it links no OpenSSL.
- `serde_json` driven by `mlua`'s serde bridge encodes at 53 MB/s against 15 MB/s for the
  best pure-Lua encoder (lunajson). The limit is `mlua`'s table access, not serde_json, so
  `mlua` improvements are inherited by upgrading the crate.

## Options considered

1. **Rust modules through `mlua`** (`rustls`, `serde_json`). Consequences: memory safety
   for the protocol and codec code; Rust toolchain required to build from source; `ring`
   still compiles C and assembly; one more language in the monorepo.
2. **Own C bindings** (OpenSSL memory BIOs, own encoder). Consequences: no new toolchain,
   but we write and secure the C ourselves.
3. **Existing Lua bindings** (luaossl, lua-openssl). Consequences: no suitable I/O API
   (luaossl) or not built (lua-openssl).
4. **Pure Lua.** Not viable for TLS; 3.5 times slower for encoding.

## Decision

- TLS in `hecate.net` is `rustls` (with the `ring` provider, to be confirmed against
  `aws-lc-rs` when the module is written) bound through `mlua`, used as a sans-IO state
  machine: the reactor moves bytes between sockets and the TLS object.
- JSON encoding in `hecate.json` uses `serde_json` through `mlua` (supersedes the Lua
  encoder of ADR 0020); decoding stays on yyjson.
- Rust is a **build-time tool for native modules only**: the rest of the framework stays
  Lua and C (llhttp, yyjson, luv). The Rust toolchain is pinned in the bootstrap
  (`.hecate/toolchain/`), crates are locked with `Cargo.lock`, and `cargo-deny` joins
  `check-licenses`.
- Prebuilt binaries are produced in release CI so that users of the `hecate` rocks and
  Docker images do not need Rust; source builds through LuaRocks need it.

## Consequences

- Dependencies added: `mlua`, `rustls`, `serde_json` and their transitive crates (owner
  approved with this decision); the 43-crate tree of the prototype is to be audited.
- `ci-engineer` adds Rust to the matrix on three platforms (including `ring` on MSVC) and a
  native-module cache; `release-manager` handles prebuilt artefacts.
- Cross-platform builds, ALPN/SNI, client certificates and session resumption are still to
  be verified in the `net` implementation.
- Whether a LuaRocks `rust-mlua` build type suffices for rockspecs is to be verified.
- `mlua` performance improvements reach Hecate by a version bump.

## Verification

CI builds the modules on Linux, macOS and Windows; `cargo-deny` and `cargo audit` in the
security workflow; `security-reviewer` and `native-code-reviewer` review the `unsafe`
boundary and the TLS configuration defaults (certificate verification on by default).
