---
description: Serve HTTP/1.1 with hecate.http.Server, write an action that returns strings, JSON and problem details, read the request, set cookies and shut down gracefully.
hecate: "0.x"
lua: "5.5"
order: 8
---

# Serve HTTP

This guide shows how to start an HTTP/1.1 server, answer requests and stop it cleanly. It assumes you know
[how to connect and serve over TCP](connect-and-serve-over-tcp.md).

`hecate.http` is a protocol layer. It has no routing: the [action](../reference/glossary.md#http) you give to the server is one
function that receives every request. Routing, filters and validation come from higher layers.

The server, the client and the parser need the native llhttp module (`lua tools/run.lua build-native http`). `require("hecate.http")` works without it: the message model, forms and cookies are there, `Server`, `Client` and `Parser` are nil, and `http.available()` returns `false` and the reason.

Calls that wait on the network *suspend* the running
[coroutine](../reference/glossary.md#concurrency). Run the server inside `reactor.run`. For the
reasons behind the design, read [The HTTP model](../explanation/http-model.md).

## Hello world

Four lines serve `hello` on `127.0.0.1:8080`. Run the file, then ask it from another terminal
with `curl http://127.0.0.1:8080/`. It answers `hello`.

<!-- example: packages/http/examples/hecate.http.Server.hello.lua -->
```lua
-- The smallest server: it listens on 127.0.0.1:8080 and answers every
-- request with "hello".
local http, reactor = require("hecate.http"), require("hecate.reactor")
local function action() return http.Response(200, { content = "hello\n" }) end
reactor.run(function() http.Server(action, { port = 8080 }):serve() end)
-- Answers: hello
```

The server logs one informational record at start, `http.Server: listening on 127.0.0.1:8080
(loopback only)`, to the standard error stream through the default logger (`log.default()`). Pass
your own `logger` (a `hecate.log.Logger`) to replace it.

## Start a server

`http.Server(action, options?)` creates a server. Nothing is bound yet. `server:listen()` binds
the address and returns the listener. `server:serve(listener?)` accepts connections until the
server is shut down.

The example below serves three paths, asks each one with the client and shuts the server down.

<!-- example: packages/http/examples/hecate.http.Server.lua -->
```lua
-- A server on a free port. The action answers with a string, JSON text
-- (http never serialises) and a function that streams its content, then
-- the server shuts down.
local json = require("hecate.json")
local reactor = require("hecate.reactor")
local http = require("hecate.http")

local function action(request)
  if request.path == "/hello" then
    return http.Response(200, { content = "hello" })
  elseif request.path == "/user" then
    return http.Response(200, { content = json.encode({ name = "Ada" }) })
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
  local server = http.Server(action, { port = 0 })
  local listener = server:listen()
  local serving = reactor.fork(server.serve, server, listener)
  local base = "http://127.0.0.1:" .. listener:local_address().port
  local client <close> = http.Client()
  print(client:get(base .. "/hello"):read_content())
  -- Prints: hello
  print(client:get(base .. "/user"):read_content())
  -- Prints: {"name":"Ada"}
  print((client:get(base .. "/count"):read_content():gsub("\n", " "):gsub(" $", "")))
  -- Prints: 1 2 3
  print(client:get(base .. "/missing").status)
  -- Prints: 404
  server:shutdown()
  reactor.join(serving)
end)
```

`serve` returns once every connection has ended, so fork it, as the example does, and join it
after `shutdown`.

## Choose the address

The default host is `127.0.0.1`: the server is reachable from this machine only. To serve every
interface, say so:

```lua
local server = http.Server(action, { host = "0.0.0.0", port = 8080 })
```

Use `"::"` for IPv6. The host must be a numeric address. A name is an `ArgumentError`, because a
name can resolve to several addresses. Port `0` picks a free port, and
`listener:local_address().port` tells you which. The default port is 8080.

> [!WARNING] The default is loopback on purpose
> A server that starts on every interface by default is exposed by accident. Opening it is one
> option away, and it is yours to set. In a container the server must listen on `"0.0.0.0"`:
> with the default, `docker run -p 8080:8080` publishes a port that nothing answers, and the
> symptom is a connection that is reset or closed at once, from the host.

## Know the defaults

- `host` is `127.0.0.1` and `port` is 8080 (see above).
- Request content is limited to 1 MiB: more is a 413, before your action runs when the length is
  declared. `request_timeout` is 300 seconds for a whole request.
- There is no timeout on the action and no limit on the number of connections.
- Every limit and its default is in [the limits table](http-limits-timeouts-and-tls.md#set-limits)
  and in `Server.DEFAULTS`.

## Write an action

The action takes a `Request` and returns a `Response`. It runs in its own
[scope](../reference/glossary.md#concurrency), in its own coroutine, once per request. It may
suspend: read the content, call a database, call the client.

A `Request` has these fields and methods:

- `method`, for example `"POST"`.
- `target`, the raw request target, and its parts `path` and `query` (`nil` without a query). `path` and `query` are raw: as received, not percent-decoded and not normalised, so `%2F` is still `%2F` and dot segments stay.
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
| a function `content(write, flush)` | a stream (see [Stream HTTP content](stream-http-content.md)) |

`http` is bytes only and never serialises. `http.Response` raises an `ArgumentError` for content
that is not nil, a string or a function, a table included. Encode the table yourself
(`json.encode`) and set `Content-Type`, as the example does. (A table set on a response object that
bypassed the constructor reaches the server as an error: the client gets the generic 500 problem
details response and the server logs the failure.)

The server never sends content for HEAD, 1xx, 204 and 304. It sets `Date`, `Content-Length`,
`Transfer-Encoding` and `Connection` itself and replaces yours. The one exception is a streamed
content: a `Content-Length` you set is then the length you promise, and when the function writes
another number of bytes the server cuts the content and closes the connection.

Fields are built from a table or from a `Fields` object:

```lua
local fields = http.Fields({ ["Content-Type"] = "text/plain" })
fields:add("Cache-Control", "no-store")
return http.Response(200, { fields = fields, content = "ready" })
```

`Fields` raises a `hecate.core.ArgumentError` for a value with CR, LF, NUL or another control character
(HTAB is allowed) and for a name that is not a token. A response that is not
valid (a status outside 100 to 599, content of another type) becomes a 500.

## Answer errors with problem details

An error response is [problem details](../reference/glossary.md#http).

`http.problem.response(status, detail?)` builds an
[RFC 9457](https://www.rfc-editor.org/rfc/rfc9457) problem details response: the media type is
`application/problem+json`, `type` is `about:blank`, `title` is the reason phrase. The status
must be from 400 to 599.

```lua
return http.problem.response(409, "The name is already taken.")
```

When the action raises an error, the server sends a generic problem details response chosen by
the class of the error. The text of the error never reaches the client: not a message, not an
address, not an error number. A request over the content limit is a 413, a malformed form is a
400 and anything else is a 500. The server also logs the error at `error` severity through the default logger (or your `logger`),
and passes it to `on_error`, which you can use to take over:

```lua
local server = http.Server(action, {
  on_error = function(err) io.stderr:write(tostring(err), "\n") end,
})
```

## Cookies

`request:cookies()` returns a table from name to value. `http.SetCookie` formats a `Set-Cookie`
field, and `response:set_cookie(cookie)` adds it. Each cookie is sent in its own `Set-Cookie` field.

```lua
local session = request:cookies().session
local response = http.Response(200, { content = "welcome" })
response:set_cookie(http.SetCookie({
  name = "session", value = "abc123", path = "/", http_only = true, secure = true, same_site = "Lax",
}))
return response
```

## Stop the server

`server:shutdown(grace_timeout?)` stops accepting, closes the connections that wait for a request and
lets each request in flight finish. Their answers carry `Connection: close`. It returns when
`serve` has returned. When the [grace period](../reference/glossary.md#http) expires (30 seconds by default), the remaining requests are
cancelled. There is no `<close>` form for a server: `shutdown` suspends while it waits for the
requests, and a `<close>` scope cannot suspend.

A program stops its server on `SIGINT` or `SIGTERM`: one computation waits for the signal, and
`select` returns when it arrives.

<!-- example: packages/http/examples/hecate.http.Server.shutdown.lua -->
```lua
-- Stop a server on SIGINT or SIGTERM: one computation waits for the signal,
-- another serves, and the shutdown gives the requests in flight ten seconds.
-- A `<close>` scope cannot stop a server, because `shutdown` suspends while
-- it waits for them. Here a request stands in for the signal.
local reactor = require("hecate.reactor")
local http = require("hecate.http")

local function action() return http.Response(200, { content = "hello" }) end

reactor.run(function()
  local server = http.Server(action, { port = 0 })
  local listener = server:listen()
  local serving = reactor.fork(server.serve, server, listener)
  local signalled = reactor.fork(reactor.wait_signal, "sigint", "sigterm")
  -- In a program, only the signal ends the wait.
  local finished = reactor.fork(function()
    local client <close> = http.Client()
    print(client:get("http://127.0.0.1:" .. listener:local_address().port .. "/"):read_content())
    -- Prints: hello
  end)
  reactor.select(signalled, finished)
  server:shutdown(10)
  reactor.join(serving)
end)
```

## What the server does for you

- It serves keep-alive connections, and answers pipelined requests in order.
- It answers `Expect: 100-continue` when the action first reads the content. Any other
  expectation is a 417.
- It answers an HTTP/1.1 request without exactly one `Host` field with a 400.
- It answers an `Upgrade` or `CONNECT` request with a 501.

It does not run a timeout on the action. An action that never returns holds its connection.
Bound it yourself with `reactor.deadline` inside the action. See
[Deadlines and cancellation](deadlines-and-cancellation.md).

## Next steps

- [Stream HTTP content](stream-http-content.md)
- [Handle forms and multipart](handle-forms-and-multipart.md)
- [Set limits, timeouts and TLS on the HTTP server](http-limits-timeouts-and-tls.md)
- [Use the HTTP client](use-the-http-client.md)
- [The HTTP model](../explanation/http-model.md)
