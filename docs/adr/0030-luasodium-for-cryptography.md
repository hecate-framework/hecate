# 0030 — `luasodium` is the cryptography dependency of Hecate

- **Status:** Accepted
- **Date:** 2026-11-14
- **Deciders:** project owner (accepted by the project owner, 2026-11-14, on pull request #200)
- **Packages:** security (and any package that needs a cryptographic primitive for a security purpose)
- **Related:** [ADR 0014](0014-wire-protocol-drivers-in-lua.md), [ADR 0021](0021-rust-native-modules.md), [ADR 0028](0028-cli-sha256-rock-behind-a-seam.md) (the CLI's checksum, not a security use), OQ-45 (issue [#58](https://github.com/hecate-framework/hecate/issues/58)), [spike OQ-13](../spikes/OQ-13-standalone-executable.md)

## Context

The `security` package (authentication, password hashing, tokens, authorisation policies) needs cryptography, and so do
other packages from time to time. The owner's direction of 2026-11-14: cryptography and hashing for security purposes belong
to the `security` package, which depends on `luasodium` (Lua bindings to libsodium) instead of implementing algorithms or
choosing a library per package, and Hecate's default password hashing is argon2id.

Checked on 2026-11-14 with the source tarball of `luasodium` 2.4.1 supplied by the owner (its host `buffering.party` is
blocked in the cloud environment): it builds on Lua 5.5.1 against libsodium 1.0.18 on Linux (Ubuntu 24.04), and through it
SHA-256 and HMAC-SHA-256 give the same results as `sha256sum` and OpenSSL, and argon2id is the default password hash
(`crypto_pwhash_str` and its verify function work). It is MIT licensed, at version 2.4.1-2 on luarocks.org with about
31,700 downloads. libsodium itself is ISC licensed and needs to be present on the machine. Not checked: Windows and macOS
builds of `luasodium`, or bundling libsodium.

## Options considered

1. **`luasodium`** (libsodium, a widely used and audited library, with an API designed to be hard to misuse). Argon2id is a
   first-class primitive. Consequences: a native library (libsodium) next to the rock on every platform; the primitives
   libsodium chose not to include are not there.
2. **An own binding to a Rust crypto crate**, built in the way of ADR 0021 (`mlua`). Full control and no system library;
   a crate and a binding of ours to maintain, audit and build on three platforms.
3. **OpenSSL through an existing binding** (such as `luaossl`). Broad algorithm coverage; a larger and more error-prone
   API, and a system library that is harder to ship on Windows.
4. **Pure-Lua implementations.** No native dependency; not acceptable for password hashing (memory-hard and constant-time
   requirements) and slow.

## Decision

- `security` depends on `luasodium` (option 1), and uses it for password hashing (argon2id by default), message
  authentication, random bytes and the other primitives it needs. No package implements a cryptographic algorithm of its own
  for a security purpose.
- Any other package that needs a cryptographic primitive for a security purpose uses `luasodium` as well, directly (as a
  third-party rock) and not through `security`, which has other responsibilities and sits above many packages.
- Where one package needs a primitive that libsodium does not provide, that package takes a small dedicated rock for it;
  no shared package is created for such primitives.
- The CLI keeps its own checksum dependency for lock files and downloaded archives (ADR 0028); that is not a security use of
  cryptography in the sense of this ADR.

## Consequences

- The libsodium library becomes a requirement of the packages that use `luasodium`, on every platform: installed from the
  system on Linux and macOS, and shipped by the installer on Windows (the setup executable already ships DLLs, ADR 0029).
  How it is provided in Docker images and in binary rocks is decided with the `security` item.
- `THIRD_PARTY_NOTICES` records `luasodium` (MIT) and libsodium (ISC) when either is vendored or shipped.
- A dependency on `luasodium` is added to the rockspec of a package only when this ADR is accepted and the package needs it
  (the `security` item).
- `docs/architecture/overview.md` shows `security` and the others as depending on a third-party rock, not on a new layer.

## Verification

Before `security` is implemented: a throwaway workflow on Linux, macOS and Windows installs `luasodium` and libsodium and
runs the checks of 2026-11-14 (hashing, message authentication, argon2id hash and verify) on Lua 5.5. A failure on a platform
reopens the options above for that platform.
