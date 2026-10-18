---
description: Open and accept TLS connections with hecate.net, with the system trust store or a private certificate authority.
hecate: "0.x"
lua: "5.5"
---

# Use TLS as a client and as a server

This guide shows how to wrap a connection in TLS, with a public server or a private
certificate authority, and how to accept TLS connections. It was written for hecate 0.x
and Lua 5.5.

TLS needs the native module of `hecate-net`, built from Rust sources. In a checkout, run
`lua tools/run.lua build-native`. Call `net.tls.available()` to test for it: it returns
`true`, or `false` and the reason. Without the module, TLS calls raise `TlsError` with
`context.reason = "native_missing"`.

Certificate verification is always on. No option turns it off.

## Connect to a public server

`net.connect_tls(host, port, options?)` connects, then runs the handshake. It verifies
the server certificate against the trust store of the operating system. A server with a
public certificate needs no option.

```lua
local client <close> = net.connect_tls("example.org", 443)
client:write("GET / HTTP/1.0\r\n\r\n")
print(client:reader():read_line())
client:shutdown()
```

`shutdown()` sends `close_notify`. Call it before `close()`: closing cannot send it, and
a peer then sees a truncation, not a clean end.

The host name is also the server name for SNI and for the identity check. Pass
`server_name` to override it.

On macOS and Windows the system verifier may do revocation checks that block the reactor
while they run ([ADR 0024](https://github.com/hecate-framework/hecate/blob/main/docs/adr/0024-tls-trust-store.md)).

## Trust a private certificate authority

Give the certificate of your authority as PEM text in `ca_pem`. It is added to the system
trust store. Add `system_roots = false` to trust nothing else.

```lua
local client <close> = net.connect_tls("localhost", port, {
  ca_pem = ca_pem, system_roots = false,
})
```

The tested example
[`hecate.net.connect_tls.lua`](https://github.com/hecate-framework/hecate/blob/main/packages/net/examples/hecate.net.connect_tls.lua)
runs a client and a server against the test authority of the package. It prints
`secure hello`.

Options such as `verify` or `insecure` do not exist. An unknown option, or one that
belongs to the other kind of configuration, raises `ArgumentError`.

## Other client options

| Option | Meaning |
|---|---|
| `alpn` | List of protocol names to offer, for example `{ "h2", "http/1.1" }`. |
| `cert_pem`, `key_pem` | Client certificate and key, given together, for mutual TLS. |
| `tls_config` | A configuration built once with `net.tls.client_config`, for many connections. It excludes the other TLS options. |
| `handshake_deadline` | Seconds allowed for the handshake, 10 by default. |

Transport options (`nodelay`, `keepalive`, `keepalive_delay`, `family`) are those of
`net.connect`.

## Accept TLS connections

Build a server configuration once, then accept a TCP connection and run its handshake.

```lua
local config = net.tls.server_config({
  cert_pem = cert_pem, key_pem = key_pem, alpn = { "echo" },
})
local listener <close> = net.listen("127.0.0.1", 0)
local peer <close> = net.tls.accept(listener:accept(), config)
print(peer:alpn())
```

The tested example is
[`hecate.net.tls.accept.lua`](https://github.com/hecate-framework/hecate/blob/main/packages/net/examples/hecate.net.tls.accept.lua).
It prints `hello over echo`.

Accepting is deliberately two steps. In a server, fork the handshake of each connection,
inside a [deadline](net-deadlines.md), so that one silent client cannot stall the accept
loop:

```lua
while true do
  local stream = listener:accept()
  reactor.fork(function()
    local peer <close> = reactor.deadline(5, net.tls.accept, stream, config)
    -- serve `peer`
  end)
end
```

`tls.accept` takes ownership of the stream as soon as its arguments are valid. Its own
`handshake_deadline` bounds the handshake anyway.

To require client certificates, pass `client_ca_pem` to `net.tls.server_config`. After the
handshake, `peer:requested_server_name()` returns the SNI the client sent, and
`peer:peer_certificate()` returns the client certificate.

## Handle failures

A `TlsError` is a `NetworkError`. `context.reason` names the kind when it is recognised:

| Reason | Meaning |
|---|---|
| `untrusted_issuer` | The authority is not trusted. Add it with `ca_pem`. |
| `name_mismatch` | The certificate does not name the host. |
| `expired`, `not_yet_valid`, `revoked` | The certificate is not valid now. |
| `alpn_mismatch` | No protocol in common. |
| `truncated`, `transport_ended` | The peer ended without `close_notify`. |
| `stalled` | The handshake did not progress. |

On macOS and Windows the system verifiers report many failures as text only, so `reason`
may be missing there.

## See also

- [Connect and serve over TCP](net-tcp.md)
- [ADR 0024: TLS trust store](https://github.com/hecate-framework/hecate/blob/main/docs/adr/0024-tls-trust-store.md)
