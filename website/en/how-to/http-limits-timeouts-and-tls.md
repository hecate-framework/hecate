---
description: Set the limits, timeouts and TLS options of hecate.http.Server, read the defaults, and configure TLS trust for hecate.http.Client.
hecate: "0.x"
lua: "5.5"
order: 12
---

# Set limits, timeouts and TLS on the HTTP server

This guide shows how to tighten or relax the bounds of `http.Server`, and how to serve and call
HTTPS. It is written for hecate 0.x and Lua 5.5. Every limit is an option of the server, and
every option has a default, so a server is never unbounded by accident. For the reasons behind
the values, read [The HTTP model](../explanation/http-model.md#why-these-defaults).

## Set limits

Pass the options when you create the server. The parser limits go in the `parser` table.
`http.Server.DEFAULTS` holds the values the server applies.

<!-- example: packages/http/examples/hecate.http.Server.limits.lua -->
```lua
-- Limits, as options. A server that accepts 16 bytes of content refuses a larger request
-- with a 413 before the handler runs, and the parser limits go in the `parser` table.
local reactor = require("hecate.reactor")
local http = require("hecate.http")

local ran = false
local function handler()
  ran = true
  return http.Response(200, { content = "ok" })
end

reactor.run(function()
  local server = http.Server(handler, {
    port = 0,
    max_content = 16,
    head_timeout = 5,
    idle_timeout = 30,
    max_connections = 100,
    parser = { max_fields = 20 },
  })
  local listener = server:listen()
  local serving = reactor.fork(server.serve, server, listener)
  local url = "http://127.0.0.1:" .. listener:local_address().port .. "/"
  local client <close> = http.Client()
  local small = client:post(url, "0123456789")
  print(small.status, small:read_content())
  ran = false
  local large = client:post(url, ("x"):rep(17))
  print(large.status, large.fields:get("Content-Type"), ran)
  server:shutdown()
  reactor.join(serving)
end)
-- Prints: 200	ok
-- 413	application/problem+json	false
```

An unknown option, or a value out of range, raises an `ArgumentError` when the server is created.
A limit that is exceeded is answered with problem details and the connection closes, except where
the table says otherwise.

| Limit | Option | Default | When exceeded |
|---|---|---|---|
| Request target | `parser.max_target_size` | 8192 bytes | 414 |
| One field name or value | `parser.max_field_size` | 8192 bytes | 431 |
| Fields in a head | `parser.max_fields` | 100 | 431 |
| Raw bytes of a head | `parser.max_head_size` | 65536 bytes | 431 |
| Request content | `max_content` | 1048576 bytes | 413 |
| Head, from its first byte to its end | `head_timeout` | 60 s | 408 |
| Wait for the next request | `idle_timeout` | 75 s | closed without an answer |
| Between two reads of content | `content_timeout` | 60 s | 408 |
| From the end of the head to the last byte of content | `content_deadline` | 300 s | 408 |
| Draining unread content after the response | `drain_timeout` | 5 s | the connection closes |
| One write to the client | `write_timeout` | 60 s | the connection closes |
| Connections served at once | `max_connections` | none | the excess waits in the backlog |
| Pending connections in the kernel | `backlog` | 128 | the kernel refuses |

> [!WARNING] `max_connections` has no limit by default
> The descriptor limit of the process, `idle_timeout` and `head_timeout` bound the resource. An
> internet-facing server should set it: about 80 percent of the descriptor limit, for instance
> 50000 with `ulimit -n 65536`. Raise the descriptor limit too (`ulimit -n`, or `LimitNOFILE` in
> systemd).

A few rules help when you choose values:

- `head_timeout` is a deadline on the whole head. Bytes that keep arriving do not extend it. That
  is what stops a client that sends one byte per interval.
- `content_timeout` is a timeout between reads. A slow but steady upload is not cut. The total
  time of a body is bounded by `content_deadline`, so raise it for uploads that legitimately last
  longer than five minutes.
- Behind a reverse proxy, give the proxy an upstream keep-alive timeout shorter than
  `idle_timeout`.
- Pipelining needs no option: the server reads at most 16 KiB at a time, and only after it has
  answered every request already parsed.

When the accept loop meets descriptor exhaustion (`EMFILE`, `ENFILE`) or any other accept
failure, connections in service keep being served. The loop backs off from 50 ms to 1 s,
resumes by itself and reports the burst once to `logger` and `on_error`.

## Deadline for a handler

The server has no per-request timeout for the handler. Bound it inside:

```lua
local function handler(request)
  return reactor.deadline(5, function()
    return http.Response(200, { content = slow_lookup(request.path) })
  end)
end
```

When the deadline expires, `reactor.deadline` raises `DeadlineExceededError`, and the server
answers with a generic 500. Catch it yourself to answer 503 instead.

## TLS

Pass the `tls` option to serve HTTPS. It takes the options of `net.tls.server_config`, or a
configuration built by it. The ALPN protocol list defaults to `http/1.1`. TLS needs the TLS native
module of `hecate.net`.

```lua
local function read(path)
  local file = assert(io.open(path, "rb"))
  local text = file:read("a")
  file:close()
  return text
end

local server = http.Server(handler, {
  host = "0.0.0.0",
  port = 8443,
  tls = { cert_pem = read("server.pem"), key_pem = read("server.key") },
})
```

Each accepted connection handshakes in its own computation, never in the accept loop. A client
that stays silent holds nothing but its own slot. Three options bound handshakes. They need `tls`:

| Option | Default | Bounds |
|---|---|---|
| `handshake_timeout` | 10 s | the time of one handshake (the connection is dropped) |
| `max_handshakes` | 64 | handshakes in progress at once (the excess waits in the backlog) |
| `max_handshake_bytes` | 65536 | bytes read from a client before the handshake ends |

A failed handshake sends the client nothing. The `logger` option (a `hecate.log.Logger`) receives
`http.Server: TLS handshake failed` with the peer address and the class of the reason. Nothing
else leaves the server. For client certificates and ALPN, see
[TLS client and server](tls-client-and-server.md).

### The client

`http.Client` trusts the system store, and verification cannot be turned off
([TLS trust and security defaults](../explanation/tls-trust-and-security.md)). The `tls` option
of the client adds to that:

```lua
local client = http.Client({
  tls = { ca_pem = read("ca.pem"), system_roots = false, cert_pem = read("client.pem"), key_pem = read("client.key") },
})
```

- `ca_pem` adds a trust anchor, for a private authority.
- `system_roots = false` trusts `ca_pem` only.
- `cert_pem` and `key_pem` present a client certificate.

The client's `connect_timeout` covers the TLS handshake too.

## Next steps

- [Serve HTTP](serve-http.md)
- [The HTTP model](../explanation/http-model.md)
