---
description: Open TLS connections with the system trust store or a private CA, serve TLS with the two-step accept, negotiate ALPN, require client certificates and read TLS errors.
hecate: "0.x"
lua: "5.5"
order: 2
---

# TLS client and server

This guide shows how to use TLS with `hecate.net`: a client that verifies a server, a server
that accepts clients, and the errors you can meet. It is written for hecate 0.x and Lua 5.5.
It assumes you know [how to connect and serve over TCP](connect-and-serve-over-tcp.md).

TLS is provided by [rustls](https://github.com/rustls/rustls) inside a native module. Build it
once with `lua tools/run.lua build-native`. Without it, `net.tls.available()` returns `false`
and the reason, and every TLS call raises `TlsError` with `context.reason` set to
`"native_missing"`.

> [!WARNING] Verification cannot be turned off
> There is no option that disables certificate verification, and none will be added. A mistyped
> or unsafe option such as `verify = false` raises `ArgumentError`. See
> [TLS trust and security defaults](../explanation/tls-trust-and-security.md) for the reasons.

## Connect to a public server

With no option, `net.connect_tls` verifies the server certificate against the operating system's
trust store. A public server works as is.

```lua
local stream <close> = net.connect_tls("example.org", 443, { alpn = { "http/1.1" } })
```

The host is also the server name: it is sent as SNI (Server Name Indication, RFC 6066), and the certificate must match it (RFC 6125).
Pass `server_name` when you connect to an address but the certificate names a host.

## Trust a private certificate authority

Use `ca_pem` to add the trust anchors of your own authority to the system store. Add
`system_roots = false` to trust only `ca_pem`. That gives you a closed trust set, which is
also what the tests of hecate use.

<!-- example: packages/net/examples/hecate.net.connect_tls.lua -->
```lua
-- A TLS client against a local server whose certificate comes from the test CA of this package.
-- With no option, `connect_tls` verifies the server against the operating system's trust store;
-- here `ca_pem` names the private CA and `system_roots = false` trusts nothing else. Verification
-- cannot be disabled. Needs the native TLS module (`lua tools/run.lua build-native`).
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
  client:shutdown() -- close_notify: a clean end, not a truncation
end)
-- Prints: secure hello
```

`system_roots = false` requires `ca_pem`. The client ends the conversation with `shutdown()`, which
sends `close_notify`. See [Close a TLS stream](#close-a-tls-stream).

To connect many times with the same options, build the configuration once with
`net.tls.client_config(options)` and pass it as `tls_config`. It excludes the other TLS options.
Without it, `connect_tls` builds a configuration per call. Loading the system store is the
costly part, so cache it when you connect often.

## Serve TLS

A server first builds a configuration from its certificate chain and key:

```lua
local config = net.tls.server_config({ cert_pem = chain, key_pem = key })
```

Then it accepts connections in two steps, on purpose:

```lua
local peer = net.tls.accept(listener:accept(), config)
```

`listener:accept()` returns the TCP stream. `tls.accept` runs the handshake of that one
connection and takes ownership of the stream: if the handshake fails, the stream is closed.

> [!TIP] Fork the handshake
> Never run the handshake in the accept loop itself. A client that connects and then says nothing
> would stall every other client. Fork one coroutine per connection and run `tls.accept` inside it.
> The handshake is bounded anyway by `handshake_deadline`, which is 10 seconds by default. Pass
> `{ handshake_deadline = 5 }` as the third argument to change it. On expiry the stream is closed and
> `DeadlineExceededError` is raised.

The example below negotiates an application protocol with ALPN (Application-Layer Protocol Negotiation, RFC 7301). The server offers `echo`; the
client asks for it; each side reads the result with `stream:alpn()`.

<!-- example: packages/net/examples/hecate.net.tls.accept.lua -->
```lua
-- The server side of TLS, in the two-step form that is the idiom: accept the TCP connection,
-- then run the handshake of that one connection. A server forks the handshake per connection
-- (inside `reactor.deadline`) so that one silent client cannot stall the accept loop; this
-- example handles a single connection inline. Needs the native TLS module
-- (`lua tools/run.lua build-native`).
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
  local config = net.tls.server_config({
    cert_pem = fixture("server.pem"), key_pem = fixture("server.key"), alpn = { "echo" },
  })
  local listener <close> = net.listen("127.0.0.1", 0)
  reactor.fork(function()
    local peer <close> = net.tls.accept(listener:accept(), config)
    local line = peer:reader():read_line()
    peer:write(("%s over %s\n"):format(line, peer:alpn()))
    peer:read() -- until the client's close_notify: the end of the conversation
  end)
  local client <close> = net.connect_tls("localhost", listener:local_address().port, {
    family = "inet", ca_pem = fixture("ca.pem"), system_roots = false, alpn = { "echo" },
  })
  client:write("hello\n")
  print(client:reader():read_line())
  client:shutdown() -- close_notify: a clean end, not a truncation
end)
-- Prints: hello over echo
```

A server can read the name a client asked for with `stream:requested_server_name()`. It does not
select a certificate from it: there is one certificate chain per configuration.

## Require client certificates

Mutual TLS asks the client to prove who it is. On the server, pass `client_ca_pem`: the
authority that signed the client certificates. Clients then need `cert_pem` and `key_pem`.

The example forks the handshake of every connection, bounds it with `handshake_deadline`, and
requires a client certificate.

<!-- example: packages/net/examples/hecate.net.tls.server_config.lua -->
```lua
-- A TLS server that requires client certificates (mutual TLS). `client_ca_pem` names the
-- authority that signed the client certificates. The accept loop forks the handshake of each
-- connection and bounds it with `handshake_deadline`, so that one silent client cannot stall it.
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
  local config = net.tls.server_config({
    cert_pem = fixture("server.pem"), key_pem = fixture("server.key"), client_ca_pem = fixture("ca.pem"),
  })
  local listener <close> = net.listen("127.0.0.1", 0)
  local acceptor = reactor.fork(function()
    while true do
      local connection = listener:accept()
      reactor.fork(function()
        -- The handshake owns `connection`: it is closed if the handshake fails.
        local ok, peer = pcall(net.tls.accept, connection, config, { handshake_deadline = 5 })
        if not ok then return end
        local reader, writer = peer:reader(), peer:writer()
        writer:write("welcome " .. reader:read_line() .. "\n")
        writer:flush()
        peer:read() -- until the client's close_notify
        peer:close()
      end)
    end
  end)
  local client <close> = net.connect_tls("localhost", listener:local_address().port, {
    family = "inet", ca_pem = fixture("ca.pem"), system_roots = false,
    cert_pem = fixture("client.pem"), key_pem = fixture("client.key"),
  })
  local reader, writer = client:reader(), client:writer()
  writer:write("alice\n")
  writer:flush()
  print(reader:read_line())
  client:shutdown()
  acceptor:cancel()
end)
-- Prints: welcome alice
```

> [!NOTE]
> The server does not check client certificates for revocation: it configures no revocation
> lists.

## Close a TLS stream

TLS ends cleanly with a `close_notify` alert (RFC 8446, section 6.1). `close()` never suspends, so it cannot send one.
Call `shutdown()` first, then let `<close>` run:

```lua
stream:shutdown() -- sends close_notify; suspends
```

On the receiving side, `read` returns `nil` after the peer's `close_notify`. When the transport
ends without it, `read` raises `TlsError` with the reason `truncated`, because the data may be incomplete.

## Read a TLS error

A failed handshake or verification raises `TlsError`. `context.reason` names the kind when it
is recognised:

| Reason | Meaning |
|---|---|
| `untrusted_issuer` | The certificate chain does not end in a trusted authority. |
| `name_mismatch` | The certificate is not valid for the server name. |
| `expired`, `not_yet_valid` | The certificate is outside its validity period. |
| `revoked` | The authority revoked the certificate. |
| `alpn_mismatch` | The two sides share no application protocol. |
| `truncated` | The transport ended without `close_notify`: the data may be incomplete. |
| `transport_ended` | The transport ended during the handshake. |
| `stalled` | The TLS session made no progress. |
| `native_missing` | The native TLS module is not built. |

<!-- example: packages/net/examples/hecate.net.TlsError.lua -->
```lua
-- A failed verification raises a `TlsError` whose `context.reason` names the kind of failure.
-- Here the client trusts only another authority than the one that signed the server's
-- certificate. Needs the native TLS module (`lua tools/run.lua build-native`).
local core = require("hecate.core")
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
    local ok = pcall(net.tls.accept, listener:accept(), config) -- the client abandons the handshake
    assert(not ok)
  end)
  local ok, err = pcall(net.connect_tls, "localhost", listener:local_address().port, {
    family = "inet", ca_pem = fixture("other_ca.pem"), system_roots = false,
  })
  assert(not ok and core.is_instance_of(err, net.TlsError))
  ---@cast err any -- an error value, not the stream that `pcall` is typed to return
  print(err.context.reason)
end)
-- Prints: untrusted_issuer
```

On macOS and Windows the operating system's verifier reports many failures as text only. Then
`context.reason` is absent and the message carries the cause. Test the reason with a fallback, not
as an exhaustive list.

## Know the platform differences

- On macOS and Windows the system verifier may check revocation over the network during the
  handshake. That call blocks the reactor until it completes. Use `system_roots = false` when
  that is unacceptable.
- macOS refuses a server certificate valid for more than 398 days, even when its authority was
  added with `ca_pem`. Use shorter certificates, or `system_roots = false`.
- An empty or incomplete system store is an error: the handshake raises `TlsError` that
  explains the cause and the remedy. Install the system certificates (the Docker images of hecate do) or
  pass `ca_pem`.

## See also

- [TLS trust and security defaults](../explanation/tls-trust-and-security.md)
- [Deadlines and cancellation on streams](deadlines-and-cancellation.md)
- Reference: [`net.connect_tls`](../reference/net/tls.md#connect_tls),
  [`tls.accept`](../reference/net/tls.md#accept),
  [`tls.server_config`](../reference/net/tls.md#server_config),
  [`TlsStream`](../reference/net/TlsStream.md), [`TlsError`](../reference/net/TlsError.md)
