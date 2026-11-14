---
description: Why hecate verifies TLS servers with the operating system's verifier, what ca_pem adds, what cannot be disabled, and the platform caveats on revocation and certificate lifetime.
hecate: "0.x"
lua: "5.5"
order: 2
---

# TLS trust and security defaults

This page explains how hecate decides whether to trust a TLS server, and which choices it makes for you. It is
written for hecate 0.x and Lua 5.5. The decision is ADR 0024 (accepted 2026-10-18). For recipes, read
[TLS client and server](../how-to/tls-client-and-server.md).

## What a client trusts by default

A TLS client must decide whether the server it reached is the one it asked for. By default, hecate lets the
operating system decide. `net.connect_tls` and `net.tls.client_config` verify the server certificate with the
verifier of the operating system.

How that works depends on the platform:

- On Windows and macOS, the operating system's own services check the chain.
- On Linux, the usual certificate directories are read.

With no option, a public server works. The Rust crate that provides this is `rustls-platform-verifier`, used with
the `ring` cryptography provider. It adds four to seven small crates per platform to the native module.

## Why the operating system's verifier

Two other designs were considered and rejected.

- **Trust only what the caller passes in `ca_pem`.** It adds nothing to the dependencies. But nothing works against
  a public server until you ship a bundle of authorities, and stores differ per platform. TLS should work out of
  the box.
- **Bundle a list of roots in hecate.** The list is the same everywhere. But it goes stale with each release, and it
  ignores what the administrator of the machine decided to trust or to distrust.

The operating system's store follows the machine's own policy. An administrator can change it without a new release
of hecate.

## What `ca_pem` adds

`ca_pem` **adds** trust anchors to the system store. It is for a private authority: a company root, or the
authority of a test environment. The system roots stay trusted.

`system_roots = false` removes the system roots and trusts only `ca_pem`, which it needs. You get a closed trust
set. You also get the verifier that is the same on every platform, with none of the operating system's policy. The
tests of hecate use it to stay hermetic.

The example connects to a local server whose certificate comes from a test authority. `ca_pem` names that
authority, and `system_roots = false` trusts nothing else:

<!-- example: packages/net/examples/hecate.net.connect_tls.lua -->
```lua
-- A TLS client against a local server whose certificate comes from the test CA
-- of this package. With no option, `connect_tls` verifies the server against
-- the operating system's trust store; here `ca_pem` names the private CA and
-- `system_roots = false` trusts nothing else. Verification cannot be disabled.
-- Needs the native TLS module (`lua tools/run.lua build-native`).
local reactor = require("hecate.reactor")
local net = require("hecate.net")

local here = debug.getinfo(1, "S").source:sub(2):match("^(.*)[/\\]") or "."
local function fixture(name)
  local file = assert(io.open(here .. "/../tests/fixtures/" .. name, "rb"))
  local pem = file:read("a")
  file:close()
  return pem
end

reactor.run(function()
  local config = net.tls.server_config({ cert_pem = fixture("server.pem"), key_pem = fixture("server.key") })
  local listener <close> = net.listen("127.0.0.1", 0)
  reactor.fork(function()
    local peer <close> = net.tls.accept(listener:accept(), config)
    local reader, writer = peer:reader(), peer:writer()
    writer:write("secure " .. reader:read_line() .. "\n")
    writer:flush()
    peer:read() -- until the client's close_notify: the end of the conversation
  end)
  local client <close> = net.connect_tls("localhost", listener:local_address().port, {
    family = "inet", ca_pem = fixture("ca.pem"), system_roots = false,
  })
  local reader, writer = client:reader(), client:writer()
  writer:write("hello\n")
  writer:flush()
  print(reader:read_line())
  -- Prints: secure hello
  client:shutdown() -- close_notify: a clean end, not a truncation
end)
```

## What cannot be disabled

Some protections have no switch at all. An option that would turn verification off does not exist, and passing one
is an error:

```lua
local core = require("hecate.core")
local net = require("hecate.net")

local ok, err = pcall(net.tls.client_config, { verify = false })
print(ok, core.name(err))
-- Prints: false	ArgumentError
```

The protections that stay on are these:

- **Verification itself.** No option installs a verifier that accepts every certificate. The only custom verifier
  is the platform one, and `ca_pem` only adds anchors. Options such as `verify` or `insecure` do not exist: passing
  them raises `ArgumentError`. So does passing a server option to a client configuration.
- **The server name check.** The certificate must be valid for the name you connect to, or for `server_name`. This
  is checked on all three platforms (RFC 6125).
- **The protocol floor.** hecate uses the defaults of rustls: TLS 1.3 and 1.2. There is no option to enable older
  versions or other cipher suites.
- **0-RTT.** It is off.

You can still make a connection insecure in your own code. You can connect to the wrong host, or trust a private
authority too widely. The library removes the switch, not the responsibility.

## An empty store is an error

If the system store is empty or incomplete, a handshake fails with an unknown issuer and raises `TlsError`. There is
no silent fallback to anything else.

When `net.connect_tls` trusts the system store and the handshake fails with the reason `untrusted_issuer`, the
message of the error gives the remedy: install the system certificates, or pass `ca_pem`.

The Docker images of hecate are planned for Phase 3. They will install the system certificates (`ca-certificates`),
so that the default works in a container, and a release check will fail if a runtime image lacks them.

## Revocation

Whether a revoked certificate is refused depends on the platform.

- **Windows and macOS:** the operating system checks revocation. It uses OCSP (the Online Certificate Status
  Protocol, RFC 6960) and certificate revocation lists, and may fetch them over the network during the handshake.
- **Linux:** no revocation checking at all.
- **`system_roots = false`:** no operating system policy and no input or output. There is no revocation checking on
  any platform.

The fetch on Windows and macOS has a cost. A hecate process runs one
[reactor](../reference/glossary.md#concurrency), the event loop that schedules all its
[coroutines](../reference/glossary.md#concurrency). That network call **blocks the reactor**, and with it every
coroutine of the process, until the responder answers or the system gives up.

The addresses come from the certificate authority, not from the server you contact. A server therefore cannot aim
the delay at an address of its own. A slow authority can still delay a handshake.

If a handshake must never block, use `system_roots = false` and accept that revocation is not checked.

On the server side, a server that asks for client certificates (`client_ca_pem`) checks them for revocation only
when you give it lists in `client_crl_pem`.

## Wider trust by default

The system store holds many authorities. With `ca_pem` alone, the trust set was narrow; by default it is wide. If
you connect only to services you run, prefer `system_roots = false` with your own authority. This restores the
narrow set.

## The 398-day rule on macOS

macOS refuses a server certificate valid for more than 398 days. It does so even when the certificate authority was
added with `ca_pem`, because the operating system's policy applies. Long-lived certificates from a private authority
therefore fail on macOS with the default trust.

Short-lived certificates, or `system_roots = false`, avoid it. The error is the system's own text: it reports "not
standards compliant", and `context.reason` may be absent.

## What is not provided yet

These are not done:

- session resumption settings;
- OCSP stapling policy;
- refreshing or fetching certificate revocation lists;
- selecting a certificate by SNI (Server Name Indication, RFC 6066) on the server;
- certificate details beyond the DER bytes of the peer certificate;
- Android (the platform verifier needs a Java runtime there).

The server side, `tls.server_config`, is unchanged by ADR 0024.

## See also

- [TLS client and server](../how-to/tls-client-and-server.md)
- [The transport model](transport-model.md)
- Reference: [`hecate.net.tls`](../reference/net/tls.md), [`TlsError`](../reference/net/TlsError.md)
