---
description: Serve HTTP/1.1 with hecate.http.Server, write a handler that returns strings, JSON and problem details, read the request, set cookies and shut down gracefully.
hecate: "0.x"
lua: "5.5"
order: 8
---

# Serve HTTP

This guide shows how to start an HTTP/1.1 server, answer requests and stop it cleanly. It is
written for hecate 0.x and Lua 5.5. It assumes you know
[how to connect and serve over TCP](connect-and-serve-over-tcp.md).

`hecate.http` is a protocol layer. It has no routing: the handler you give to the server is one
function that receives every request. Routing, filters and validation come from higher layers.

Calls that wait on the network *suspend* the running
[coroutine](../reference/glossary.md#concurrency). Run the server inside `reactor.run`. For the
reasons behind the design, read [The HTTP model](../explanation/http-model.md).

## Start a server

`http.Server(handler, options?)` creates a server. Nothing is bound yet. `server:listen()` binds
the address and returns the listener. `server:serve(listener?)` accepts connections until the
server is shut down.

The example below serves three paths, asks each one with the client and shuts the server down.

<!-- example: packages/http/examples/hecate.http.Server.lua -->
```lua
-- A server on a free port. The handler answers with a string, a table (sent as JSON) and a
-- function that streams its content, then the server shuts down.
local reactor = require("hecate.reactor")
local http = require("hecate.http")

local function handler(request)
  if request.path == "/hello" then
    return http.Response(200, { content = "hello" })
  elseif request.path == "/user" then
    return http.Response(200, { content = { name = "Ada" } })
  elseif request.path == "/count" then
    return http.Response(200, {
      content = function(write)
        for i = 1, 3 do write(i .. "\n") end
      end,
    })
  end
  return http.problem.response(404)
end

reactor.run(function()
  local server = http.Server(handler, { port = 0 })
  local listener = server:listen()
  local serving = reactor.fork(server.serve, server, listener)
  local base = "http://127.0.0.1:" .. listener:local_address().port
  local client <close> = http.Client()
  print(client:get(base .. "/hello"):read_content())
  print(client:get(base .. "/user"):read_content())
  print((client:get(base .. "/count"):read_content():gsub("\n", " "):gsub(" $", "")))
  print(client:get(base .. "/missing").status)
  server:shutdown()
  reactor.join(serving)
end)
-- Prints: hello
-- {"name":"Ada"}
-- 1 2 3
-- 404
```

`serve` returns once every connection has ended, so fork it, as the example does, and join it
after `shutdown`.

## Choose the address

The default host is `127.0.0.1`: the server is reachable from this machine only. To serve every
interface, say so:

```lua
local server = http.Server(handler, { host = "0.0.0.0", port = 8080 })
```

Use `"::"` for IPv6. The host must be a numeric address. A name is an `ArgumentError`, because a
name can resolve to several addresses. Port `0` picks a free port, and
`listener:local_address().port` tells you which. The default port is 8080.

> [!WARNING] The default is loopback on purpose
> A server that starts on every interface by default is exposed by accident. Opening it is one
> option away, and it is yours to set.

## Write a handler

The handler takes a `Request` and returns a `Response`. It runs in its own
[scope](../reference/glossary.md#concurrency), in its own coroutine, once per request. It may
suspend: read the content, call a database, call the client.

A `Request` has these fields and methods:

- `method`, for example `"POST"`.
- `target`, the raw request target, and its parts `path` and `query` (`nil` without a query).
- `fields`, a case-insensitive `Fields` object: `request.fields:get("Content-Type")`.
- `peer_address()`, `cookies()` and `media_type()`.
- `read_content(limit?)`, `stream_content()`, `read_form()` and `stream_parts()`. See
  [Stream HTTP content](stream-http-content.md) and
  [Handle forms and multipart](handle-forms-and-multipart.md).

A `Response` is created with `http.Response(status, options?)`. The options are `fields` (a
`Fields` object), `content` and `reason`. The content is one of:

| Content | Sent as |
|---|---|
| `nil` | no content |
| a string | the bytes, with `Content-Length` |
| a table | JSON, with `Content-Type: application/json` unless you set another |
| a function `content(write, flush)` | a stream (see [Stream HTTP content](stream-http-content.md)) |

The server never sends content for HEAD, 1xx, 204 and 304. It sets `Date`, `Content-Length`,
`Transfer-Encoding` and `Connection` itself and replaces yours.

Fields are built from a table or from a `Fields` object:

```lua
local fields = http.Fields({ ["Content-Type"] = "text/plain" })
fields:add("Cache-Control", "no-store")
return http.Response(200, { fields = fields, content = "ready" })
```

`Fields` refuses CR, LF and NUL in a value and names that are not tokens. A response that is not
valid (a status outside 100 to 599, content of another type) becomes a 500.

## Answer errors with problem details

`http.problem.response(status, detail?)` builds an
[RFC 9457](https://www.rfc-editor.org/rfc/rfc9457) problem details response: the media type is
`application/problem+json`, `type` is `about:blank`, `title` is the reason phrase. The status
must be from 400 to 599.

```lua
return http.problem.response(409, "The name is already taken.")
```

When the handler raises an error, the server sends a generic problem details response chosen by
the class of the error. The text of the error never reaches the client: not a message, not an
address, not an error number. A request over the content limit is a 413, a malformed form is a
400 and anything else is a 500. Pass `on_error` to receive the real error:

```lua
local server = http.Server(handler, {
  on_error = function(err) io.stderr:write(tostring(err), "\n") end,
})
```

## Cookies

`request:cookies()` returns a table from name to value. `http.SetCookie` formats a `Set-Cookie`
field, and `response:set_cookie(cookie)` adds it. Each cookie is its own line.

```lua
local session = request:cookies().session
local response = http.Response(200, { content = "welcome" })
response:set_cookie(http.SetCookie({
  name = "session", value = "abc123", path = "/", http_only = true, secure = true, same_site = "Lax",
}))
return response
```

## Stop the server

`server:shutdown(grace?)` stops accepting, closes the connections that wait for a request and
lets each request in flight finish. Their answers carry `Connection: close`. It returns when
`serve` has returned. When the grace expires (30 seconds by default), the remaining requests are
cancelled.

## What the server does for you

- It serves keep-alive connections, and answers pipelined requests in order.
- It answers `Expect: 100-continue` when the handler first reads the content. Any other
  expectation is a 417.
- It answers an HTTP/1.1 request without exactly one `Host` field with a 400.
- It answers an `Upgrade` or `CONNECT` request with a 501.

It does not run a timeout on the handler. A handler that never returns holds its connection.
Bound it yourself with `reactor.deadline` inside the handler. See
[Deadlines and cancellation](deadlines-and-cancellation.md).

## Next steps

- [Stream HTTP content](stream-http-content.md)
- [Handle forms and multipart](handle-forms-and-multipart.md)
- [Set limits, timeouts and TLS on the HTTP server](http-limits-timeouts-and-tls.md)
- [Use the HTTP client](use-the-http-client.md)
- [The HTTP model](../explanation/http-model.md)
