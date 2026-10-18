---
description: Why hecate verifies TLS servers with the operating system's verifier, what ca_pem adds, what cannot be disabled, and the platform caveats on revocation and certificate lifetime.
hecate: "0.x"
lua: "5.5"
order: 2
---

# TLS trust and security defaults

This page explains how hecate decides whether to trust a TLS server, and which choices it makes
for you. It is written for hecate 0.x and Lua 5.5. The decision is recorded in ADR 0024
(accepted 2026-10-18). For recipes, see [TLS client and server](../how-to/tls-client-and-server.md).

## What a client trusts by default

`net.connect_tls` and `net.tls.client_config` verify the server certificate with the verifier of
the operating system. On Windows and macOS the chain is checked by the operating system's own
services. On Linux the usual certificate directories are read. With no option, a public server
works.

The Rust crate that provides this is `rustls-platform-verifier`, used with the `ring`
cryptography provider. It adds four to seven small crates per platform to the native module.

## Why the operating system's verifier

Two other designs were considered and rejected.

- **Trust only what the caller passes in `ca_pem`.** It adds nothing to the dependencies, but
  nothing works against a public server until you ship a bundle of authorities, and stores differ
  per platform. TLS should work out of the box.
- **Bundle a list of roots in hecate.** The list is the same everywhere, but it goes stale with
  each release and ignores what the administrator of the machine decided to trust or to distrust.

The operating system's store follows the machine's own policy, and an administrator can
change it without a new release of hecate.

## What `ca_pem` adds

`ca_pem` **adds** trust anchors to the system store. It is for a private authority: a company
root, or the authority of a test environment. The system roots stay trusted.

`system_roots = false` removes the system roots and trusts only `ca_pem`. It needs `ca_pem`. It
gives you a closed trust set, and it uses the verifier that is the same on every platform, with
none of the operating system's policy. The tests of hecate use it to stay hermetic.

## What cannot be disabled

- **Verification itself.** No option installs a verifier that accepts every certificate. The only
  custom verifier is the platform one, and `ca_pem` only adds anchors. Options such as `verify`
  or `insecure` do not exist: passing them raises `ArgumentError`, as does passing a server option
  to a client configuration.
- **The server name check.** The certificate must be valid for the name you connect to, or for
  `server_name`. This is checked on all three platforms (RFC 6125).
- **The protocol floor.** hecate uses the defaults of rustls: TLS 1.3 and 1.2. There is no option to
  enable older versions or other cipher suites.
- **0-RTT.** It is off.

You can still make a connection insecure in your own code, by connecting to the wrong host or by
trusting a private authority too widely. The library removes the switch, not the responsibility.

## An empty store is an error

If the system store is empty or incomplete, a handshake that fails with an unknown issuer raises
`TlsError`. The error says what is missing and how to fix it: install the system certificates, or
pass `ca_pem`. There is no silent fallback to anything else.

The Docker images of hecate install the system certificates (`ca-certificates`) so that the default
works in a container. The release checks fail if a runtime image lacks them.

## Revocation

Whether a revoked certificate is refused depends on the platform.

- **Windows and macOS:** the operating system checks OCSP and certificate revocation lists, and
  may fetch them over the network during the handshake. In a reactor that call **blocks the reactor**,
  and with it every coroutine of the process, until the responder answers or the system gives up. The addresses come from the
  certificate authority, not from the server you contact, so a server cannot aim the delay at an
  address of its own. A slow authority can still delay a handshake.
- **Linux:** no revocation checking at all.
- **`system_roots = false`:** no operating system policy and no input or output: no revocation
  checking on any platform.

If a handshake must never block, use `system_roots = false` and accept that revocation is not
checked. A server that asks for client certificates (`client_ca_pem`) does not check them for
revocation: it configures no revocation lists.

## Wider trust by default

The system store holds many authorities. With `ca_pem` alone, the trust set was narrow; by default it
is wide. If you connect only to services you run, prefer `system_roots = false` with your own
authority. This restores the narrow set.

## The 398-day rule on macOS

macOS refuses a server certificate valid for more than 398 days. It does so even when the certificate
authority was added with `ca_pem`, because the operating system's policy applies. Long-lived
certificates from a private authority therefore fail on macOS with the default trust. Short-lived
certificates, or `system_roots = false`, avoid it. The error is the system's own text: it reports
"not standards compliant", and `context.reason` may be absent.

## What is not provided yet

Not done: session resumption settings, OCSP stapling policy, certificate revocation lists,
selecting a certificate by SNI on the server, certificate details beyond the DER bytes of the peer
certificate, and Android (the platform verifier needs a Java runtime there). The server side of
`tls.server_config` is unchanged by ADR 0024.

## See also

- [TLS client and server](../how-to/tls-client-and-server.md)
- [The transport model](transport-model.md)
- Reference: [`hecate.net.tls`](../reference/net/tls.md), [`TlsError`](../reference/net/TlsError.md)
