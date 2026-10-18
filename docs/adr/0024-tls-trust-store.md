# 0024 — TLS trust store: the operating system's verifier by default

- **Status:** Accepted
- **Date:** 2026-10-18
- **Deciders:** project owner (decisions of 2026-10-18; accepted the same day on the condition that the tests pass and no security concern remains, both checked below)
- **Packages:** net (and the Docker images, CI and release tooling)
- **Related:** [ADR 0021](0021-rust-native-modules.md), OQ-41, [OQ-4 report](../spikes/OQ-4-tls.md)

## Context

`net.connect_tls` first trusted only the anchors the caller passed as `ca_pem`, and failed closed
without them (OQ-41 (1)): a connection to a public site needed a CA bundle supplied by the
caller, and certificate stores differ per platform. The owner ruled out bundled roots
(`webpki-roots`) on 2026-10-14 and chose the operating system's store as the leading option; on
2026-10-18 the owner confirmed it, asked that TLS **work straight out of the box**, and agreed
that Docker images ship the system certificates and that an empty store is an error.

The crate cost, measured by adding `rustls-platform-verifier` 0.6.2 to the native crate (no
`aws-lc`: the `ring` provider stays):

| Target | Crates before | Added |
|---|---|---|
| Linux (x86_64) | 29 | 4: `rustls-platform-verifier`, `rustls-native-certs`, `openssl-probe`, `log` |
| macOS (arm64) | 29 | 7: `rustls-platform-verifier`, `security-framework`, `security-framework-sys`, `core-foundation`, `core-foundation-sys`, `bitflags`, `log` |
| Windows (x86_64) | 30 | 5 (the verifier, its Windows bindings, `log`) |

## Options considered

1. **`ca_pem` only** (the first implementation). Consequences: no new crate, but nothing works
   against a public server without the caller shipping a bundle. Rejected by the owner.
2. **A bundled root list** (`webpki-roots`). Consequences: identical everywhere, but the list
   goes stale with each release and ignores the administrator's store. Ruled out by the owner.
3. **The operating system's verifier** (`rustls-platform-verifier`). Consequences: the system
   store and its policy (Windows and macOS verify the chain with the operating system's own
   services, Linux reads the usual certificate directories), plus `ca_pem` for a private CA.
   A handful of crates. **Chosen.**

## Decision

1. `net.connect_tls` and `tls.client_config` verify the server certificate with
   `rustls-platform-verifier`, with the `ring` provider. With no option, a public server works.
2. `ca_pem` **adds** trust anchors to the system store (a private CA). The option `system_roots =
   false` trusts only `ca_pem`, which gives the caller a closed trust set and is what the
   hermetic tests use; it requires `ca_pem`.
3. Certificate verification still cannot be turned off: no option installs a verifier that
   accepts everything. The only custom verifier is the platform one.
4. **An empty or incomplete system store is an error, not a silent fallback.** A handshake that
   fails with an unknown issuer raises `TlsError` with the reason and the remedy (install the
   system CA certificates, or pass `ca_pem`).
5. **Docker runtime images install the system CA certificates** (`ca-certificates`), so that
   the default works in a container. This is a requirement of `docker/` and of the release
   checks, not an option.
6. The server side (`tls.server_config`) is unchanged.
7. Android is not a target (the platform verifier needs the Java runtime there); the crate is
   built for Linux, macOS and Windows.

## Consequences

- The native crate gains 4 to 7 crates per platform (listed above), re-checked by `cargo-deny`
  and `cargo audit` when `security.yml` lands (ADR 0021).
- `log` returns to the dependency tree through the verifier (the `logging` feature of rustls
  stays off).
- Behaviour differs by platform where the operating system decides. **Measured on macOS (CI):** the
  system verifier refuses a server certificate valid for more than 398 days ("not standards
  compliant", status -67901) even when its CA was added with `ca_pem`, so a private CA's
  long-lived server certificates fail there with the default trust; short-lived certificates, or
  `system_roots = false` (which uses the platform-independent verifier and none of the operating
  system's policy), avoid it. The hermetic tests therefore use `system_roots = false`, and one
  test per platform covers the default path.
- Tests that need no network stay hermetic. One test reaches a public server with no option and
  runs where `HECATE_NETWORK_TESTS=1` (CI sets it).

## Security review (2026-10-18)

- **No path skips verification.** The only custom verifier installed is the platform one; no option
  accepts every certificate, and `ca_pem` only adds anchors. The server name is checked on all three
  platforms (the operating system on Windows and macOS, webpki on Linux).
- **Revocation depends on the platform.** Windows and macOS check OCSP and CRLs through the operating
  system, which may fetch them over the network *inside the handshake*. In a reactor that call
  blocks the worker until the responder answers or the system gives up. The URLs come from the
  certificate authority, not from the server being contacted, so a server cannot point the stall at
  an address it controls; a slow authority can still delay a handshake. Linux does no revocation
  checking at all, as with the first implementation. Callers that must not block, or that want no
  operating-system policy, use `system_roots = false` (webpki only, no I/O).
- **Trust is wider by default.** The system store contains many authorities, where `ca_pem` alone was
  narrow. `system_roots = false` gives the narrow set back.
- **Dependencies.** `cargo audit` of the lockfile found four advisories in rustls 0.23.45 (a
  Debug output of session secrets, a brotli decompression size, an ECH buffering case, a key
  exchange downgrade with post-quantum groups). None is reachable here (no ECH, no brotli, the
  `ring` provider has no post-quantum groups, sessions are never printed), and rustls 0.23.46
  fixes all four: updated, audit clean. `cargo audit` and `cargo deny` become CI jobs with
  `security.yml` (ADR 0021).

## Verification

- CI builds the crate and runs the TLS tests on Linux, macOS and Windows; the public-server test
  proves the default trust path on all three (green on 2026-10-18).
- A test checks that the default store rejects the test CA with the documented message, and that
  `ca_pem` makes it acceptable.
- The Docker release checks fail if a runtime image lacks the system certificates.
