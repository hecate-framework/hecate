---
description: Serve HTTP/1.1 with hecate.http.Server, write an action that returns strings, JSON and problem details, read the request, set cookies and shut down gracefully.
hecate: "0.x"
lua: "5.5"
order: 8
---

# Serve HTTP

This guide shows how to start an HTTP/1.1 server with `hecate.http.Server`, answer requests and stop the server
cleanly. It is written for hecate 0.x and Lua 5.5, and assumes you know
[how to connect and serve over TCP](connect-and-serve-over-tcp.md). For the reasons behind the design, read
[The HTTP model](../explanation/http-model.md).

`hecate.http` is a protocol layer, without routing. You give the server one
[action](../reference/glossary.md#object-model-and-architecture), the function that serves a request, and the server
calls it for every request. Routing, filters and validation come from higher layers (see
[Route requests](route-requests.md)).

Calls that wait on the network *suspend* the running [coroutine](../reference/glossary.md#concurrency), Lua's unit
of execution: the coroutine waits, and the reactor runs other coroutines meanwhile. Run the server inside
`reactor.run`, which runs a function in a coroutine that the reactor manages.

> [!NOTE] The native module
> The server, the client and the parser need the native llhttp module (`lua tools/run.lua build-native http`).
> `require("hecate.http")` works without it: the message model, forms and cookies are there. `Server`, `Client` and
> `Parser` are then nil, and `http.available()` returns `false` and the reason.

## Hello world

Four lines serve `hello` on `127.0.0.1:8080`. Run the file, then ask it from another terminal with
`curl http://127.0.0.1:8080/`. It answers `hello`.

<!-- example: packages/http/examples/hecate.http.Server.hello.lua -->
```lua
-- The smallest server: it listens on 127.0.0.1:8080 and answers every
-- request with "hello".
local http, reactor = require("hecate.http"), require("hecate.reactor")
local function action() return http.Response(200, { content = "hello\n" }) end
reactor.run(function() http.Server(action, { port = 8080 }):serve() end)
-- Answers: hello
```

At start, the server logs one informational record:
`http.Server: listening on 127.0.0.1:8080 (loopback only)`. It goes to the standard error stream, through the
default logger (`log.default()`). Pass your own `logger` (a `hecate.log.Logger`) to replace it.

## Start a server

`http.Server(action, options?)` creates a server. Nothing is bound yet.

- `server:listen()` binds the address and returns the listener.
- `server:serve(listener?)` accepts connections until the server is shut down.

The example below serves three paths, asks each one with the client, then shuts the server down.

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

`serve` returns only once every connection has ended. Fork it, as the example does, and join it after `shutdown`.

## Choose the address

The default host is `127.0.0.1`: the server is reachable from this machine only. To serve every interface, say so:

```lua
local server = http.Server(action, { host = "0.0.0.0", port = 8080 })
```

- Use `"::"` for IPv6.
- The host must be a numeric address. A name raises an `ArgumentError`, because a name can resolve to several
  addresses.
- The default port is 8080. Port `0` picks a free port, and `listener:local_address().port` tells you which.

> [!WARNING] The default is loopback on purpose
> A server that starts on every interface by default is exposed by accident. Opening it is one option away, and it
> is yours to set. In a container the server must listen on `"0.0.0.0"`. With the default,
> `docker run -p 8080:8080` publishes a port that nothing answers. From the host, the symptom is a connection that is
> reset or closed at once.

## Know the defaults

- `host` is `127.0.0.1` and `port` is 8080 (see above).
- Request content is limited to 1 MiB. More is a 413, before your action runs when the length is declared.
- `request_timeout` is 300 seconds for a whole request.
- There is no timeout on the action and no limit on the number of connections.

Every limit and its default is in [the limits table](http-limits-timeouts-and-tls.md#set-limits) and in
`Server.DEFAULTS`.

## Write an action

The action takes a `Request` and returns a `Response`. The server runs it once per request, in a coroutine of its
own and in a [scope](../reference/glossary.md#concurrency) of its own: the structured-concurrency region that owns
what the action forks. The action may suspend: read the content, call a database, call the client.

### Read the request

A `Request` has these fields and methods:

- `method`, for example `"POST"`.
- `target`, the raw request target, and its parts `path` and `query` (`nil` without a query).
- `fields`, a case-insensitive `Fields` object: `request.fields:get("Content-Type")`.
- `peer_address()`, `cookies()` and `media_type()`.
- `read_content(limit?)`, `stream_content()`, `read_form()` and `stream_parts()`. See
  [Stream HTTP content](stream-http-content.md) and [Handle forms and multipart](handle-forms-and-multipart.md).

`path` and `query` are raw: as received, not percent-decoded and not normalised. `%2F` is still `%2F`, and
[dot segments](../reference/glossary.md#http) (`.` and `..`) stay.

### Build the response

`http.Response(status, options?)` creates a response. The options are `fields` (a `Fields` object), `content` and
`reason`. The content is one of:

| Content | Sent as |
|---|---|
| `nil` | no content |
| a string | the bytes, with `Content-Length` |
| a function `content(write, flush)` | a stream (see [Stream HTTP content](stream-http-content.md)) |

`http` handles bytes only and never serialises. `http.Response` raises an `ArgumentError` for content that is not
nil, a string or a function, a table included. Encode the table yourself (`json.encode`) and set `Content-Type`, as
the example does.

A table can still reach the server on a response object that bypassed the constructor. The server treats it as an
error: the client gets the generic 500 problem details response, and the server logs the failure.

Build the fields from a table, or from a `Fields` object:

```lua
local fields = http.Fields({ ["Content-Type"] = "text/plain" })
fields:add("Cache-Control", "no-store")
return http.Response(200, { fields = fields, content = "ready" })
```

`Fields` raises a `hecate.core.ArgumentError` for a name that is not a token. It raises one too for a value with CR,
LF, NUL or another control character; HTAB is allowed. A response that is not valid becomes a 500: a status outside
100 to 599, or content of another type.

### Know what the server sets

The server never sends content for HEAD, 1xx, 204, 205 and 304. A 205 goes out with `Content-Length: 0`.

The server sets `Content-Length`, `Transfer-Encoding` and `Connection` itself, and replaces yours. There are two
exceptions:

- For a streamed content, a `Content-Length` you set is the length you promise. When the function writes another
  number of bytes, the server cuts the content and closes the connection.
- A 304 keeps a `Content-Length` you set, and sends no content.

The server adds a `Date` field when the response has none. A `Date` you set is kept.

## Answer errors with problem details

An error response is [problem details](../reference/glossary.md#http): a JSON object of
[RFC 9457](https://www.rfc-editor.org/rfc/rfc9457), with the media type `application/problem+json`.

`http.problem.response(status, detail?)` builds one. Its `type` is `about:blank` and its `title` the reason phrase
of the status. The status must be from 400 to 599.

```lua
return http.problem.response(409, "The name is already taken.")
```

When the action raises an error, the server answers with generic problem details, chosen by the class of the error.
The text of the error never reaches the client: not a message, not an address, not an error number.

- An error of `hecate.http` that carries a client status keeps it. Content over the limit is a 413, a malformed
  form is a 400, and a form of another media type is a 415.
- Anything else is a 500.

The server also logs the error at the `error` severity, through the default logger or your `logger`. Then it passes
the error to `on_error`, which you can use to take over:

```lua
local server = http.Server(action, {
  on_error = function(err) io.stderr:write(tostring(err), "\n") end,
})
```

An application of `hecate.kernel` maps the errors of its domain to problem details for you: see
[Map domain errors to problem details](map-domain-errors-to-problem-details.md).

## Set cookies

`request:cookies()` returns a table from name to value. To set a cookie, format a `Set-Cookie` field with
`http.SetCookie`, and add it with `response:set_cookie(cookie)`. Each cookie is sent in its own `Set-Cookie` field.

```lua
local session = request:cookies().session
local response = http.Response(200, { content = "welcome" })
response:set_cookie(http.SetCookie({
  name = "session", value = "abc123", path = "/", http_only = true, secure = true, same_site = "Lax",
}))
return response
```

## Stop the server

`server:shutdown(grace_timeout?)` stops the server and returns once `serve` has returned. It proceeds in order:

1. It stops accepting connections.
2. It closes the idle connections: those that served a request and wait for the next, with no byte of it yet.
3. It lets each request in flight finish, one whose head has partly arrived included. Their answers carry
   `Connection: close`.
4. When the [grace period](../reference/glossary.md#http) expires (`grace_timeout`, 30 seconds by default), it
   cancels the remaining requests.

A connection accepted just before the stop, which has sent no byte yet, is not closed at once. It has 1 second, or
the grace period when that is shorter, to start its request. It is closed when no request starts.

There is no `<close>` form for a server. `shutdown` suspends while it waits for the requests, and a `<close>` scope
cannot suspend.

A program stops its server on `SIGINT` or `SIGTERM`. One computation waits for the signal, and `select` returns when
it arrives:

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

- It keeps [persistent connections](../reference/glossary.md#http) (keep-alive) open for several requests.
- It answers [pipelined](../reference/glossary.md#http) requests in request order.
- It answers `Expect: 100-continue` when the action first reads the content. Any other expectation of an HTTP/1.1
  request is a 417.
- It answers with a 400 an HTTP/1.1 request without exactly one `Host` field, and any request with several `Host`
  lines.
- It answers with a 400 a request target with a fragment (`/a#x`), and the target `*` with a method other than
  `OPTIONS`.
- It answers an `Upgrade` or `CONNECT` request with a 501.

## Bound the action yourself

The server runs no timeout on the action. An action that never returns holds its connection. Bound it yourself with
`reactor.deadline` inside the action: see
[Set limits, timeouts and TLS on the HTTP server](http-limits-timeouts-and-tls.md#deadline-for-an-action) and
[Deadlines and cancellation](deadlines-and-cancellation.md).

## See also

- [Stream HTTP content](stream-http-content.md)
- [Handle forms and multipart](handle-forms-and-multipart.md)
- [Set limits, timeouts and TLS on the HTTP server](http-limits-timeouts-and-tls.md)
- [Use the HTTP client](use-the-http-client.md)
- [The HTTP model](../explanation/http-model.md)
