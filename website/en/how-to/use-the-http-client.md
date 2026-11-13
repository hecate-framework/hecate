---
description: Send requests with hecate.http.Client, read or stream responses, reuse pooled connections, follow redirects, set deadlines and handle failures.
hecate: "0.x"
lua: "5.5"
order: 10
---

# Use the HTTP client

This guide shows how to call an HTTP server with `http.Client`. Run the calls inside `reactor.run`: each one *suspends* the running
[coroutine](../reference/glossary.md#concurrency).

## Call a JSON API

Five lines are the whole job: create the client, get, decode, use. Against a real API only the URL
changes, for example `client:get("https://api.example.org/users/42")`. The example below runs against a
local server so that it can be tested.

<!-- example: packages/http/examples/hecate.http.Client.json.lua -->
```lua
-- Call a JSON API and decode the answer. The API is a local server here;
-- with a real one only the URL changes.
local reactor = require("hecate.reactor")
local json = require("hecate.json")
local http = require("hecate.http")

local function action(request)
  -- http never serialises: the action encodes the table and names its
  -- media type
  return http.Response(200, {
    content = json.encode({ id = 42, name = "Ada" }),
    fields = http.Fields({ { "Content-Type", "application/json" } }),
  })
end

reactor.run(function()
  local server = http.Server(action, { port = 0 })
  local listener = server:listen()
  local serving = reactor.fork(server.serve, server, listener)
  local client <close> = http.Client()
  local response = client:get("http://127.0.0.1:" .. listener:local_address().port .. "/users/42")
  local user = response:read_json()
  print(response.status .. " " .. user.name)
  -- Prints: 200 Ada
  server:shutdown()
  reactor.join(serving)
end)
```

`response:read_json(limit?)` reads the content (bounded like `read_content`) and decodes it. Content
that is not JSON raises a `core.ProtocolError` whose `context.reason` is `invalid_json`; the message
never holds the content. `response:media_type()` returns the parsed `Content-Type` (`nil` when absent
or malformed), so you can check it before decoding.

## Send requests

`http.Client(options?)` creates a client with its own connection pool. Close it with `<close>`
when you are done.

The example starts a small server, sends a JSON request and reads a second response chunk by
chunk.

<!-- example: packages/http/examples/hecate.http.Client.lua -->
```lua
-- A client with its pool. The server echoes what it receives; the client
-- sends JSON, then reads a response chunk by chunk and releases its
-- connection.
local reactor = require("hecate.reactor")
local http = require("hecate.http")

local function action(request)
  local content = request:read_content()
  return http.Response(200, { content = request.method .. " " .. request.path .. " " .. #content })
end

reactor.run(function()
  local server = http.Server(action, { port = 0 })
  local listener = server:listen()
  local serving = reactor.fork(server.serve, server, listener)
  local base = "http://127.0.0.1:" .. listener:local_address().port
  local client <close> = http.Client({ request_timeout = 10 })

  local created = client:post(base .. "/items", { name = "pen" })
  print(created.status .. " " .. created:read_content())
  -- Prints: 200 POST /items 14

  local response <close> = client:get(base .. "/items/7")
  local stream = response:stream_content()
  while true do
    local chunk = stream:read()
    if chunk == nil then break end
    print(chunk)
  end
  -- Prints: GET /items/7 0

  server:shutdown()
  reactor.join(serving)
end)
```

The methods are `client:request(method, url, options?)` and the wrappers `get`, `head`, `delete`
and `options` (`client:get(url, options?)`), and `post`, `put` and `patch`
(`client:post(url, content?, options?)`).

The URL must be absolute, `http` or `https`, without userinfo. Anything else raises an
`ArgumentError` that says why, for example `http.Client:request: invalid URL: userinfo in a URL is
refused (RFC 9110 section 4.2.4)`. The client sends the `Host` field from the URL and sets `Content-Length` or
`Transfer-Encoding` itself.

## Send content

The content of a request is one of:

- a string, sent with `Content-Length`;
- a table, sent as JSON with `Content-Type: application/json`;
- a function `content(write)`, streamed with the chunked coding, and never replayed.

The per-request `options` are `fields` (a table or a `Fields` object), `content`, `form`,
`multipart`, `redirects`, `cross_origin_redirects`, `expect_continue`, `request_timeout`,
`head_timeout`, `content_timeout`, `max_content` and `max_redirects`. Any other key is an
`ArgumentError` that suggests the nearest name. `content`, `form` and `multipart` exclude each other.
`strip_on_redirect` and the other settings belong to the client (see
[`ClientOptions`](../reference/http/ClientOptions.md)). Forms are in
[Handle forms and multipart](handle-forms-and-multipart.md).

```lua
local response = client:put(base .. "/items/7", { name = "pencil" }, {
  fields = { Authorization = "Bearer " .. token },
  request_timeout = 5,
})
```

## Read the response

A call returns when the response head has arrived: `response.status`, `response.fields`. A 404 or a
500 is a normal return, not an error: test `response:is_successful()` (a 2xx) or the status. Only a
failure of the exchange raises. The content is read lazily:

- `response:read_content(limit?)` returns the whole content. The default bound is 10 MiB
  (`max_content`). Over it, it raises `http.ContentError` with `context.reason = "too_large"`.
- `response:stream_content()` returns a `ContentStream`. Nothing is buffered beyond one read.

A response whose content is not read holds its connection, and its slot in the pool, until the
content is read to its end or `response:close()` is called. `close` drops the connection. Declare
the response with `<close>` when you stream it, as the example does. Responses to HEAD, 204, 304
and zero-length content give their connection back at once.

## The pool

The client keeps connections per [origin](../reference/glossary.md#http) (scheme, host and port):

- At most 8 per origin (`max_connections_per_origin`), in use or idle. The next request waits.
- At most 64 idle connections in all (`max_idle_connections`).
- An idle connection expires after 30 seconds (`idle_timeout`). That is shorter than the 75
  seconds of the server, so the client closes first.
- A reused connection that turns out to be dead before any byte of the response arrived is
  retried once on a new one. This applies to idempotent methods with replayable content. A POST
  is never repeated.

`client:pool_stats()` reports `idle` and `origins`. `client:close()` closes the idle connections
and refuses further requests: a request on a closed client raises `core.StateError`.

## Redirects

The client follows 301, 302, 303, 307 and 308 with a `Location`, up to 10 times
(`max_redirects`). Pass `redirects = false` to receive the redirect response itself.

- 301 and 302 turn a POST into a GET. 303 turns anything but GET and HEAD into a GET.
- `Authorization`, `Cookie`, `Proxy-Authorization`, `X-Api-Key` and `X-Auth-Token` are removed
  when the origin changes. Add more names with `strip_on_redirect`.
- A 307 or 308 that would send the content to another origin is not followed. The response is
  returned unless you set `cross_origin_redirects = true`.
- A redirect from https to http is refused unless you set `allow_downgrade = true`.
- A loop, a chain that is too long, a downgrade and a bad `Location` raise a `ProtocolError`
  whose `context.reason` is `redirect_loop`, `too_many_redirects`, `downgrade` or `bad_location`.

## Deadlines

| Option | Default | Bounds |
|---|---|---|
| `connect_timeout` | 10 s | the connect and the TLS handshake |
| `head_timeout` | 30 s | the end of the request to the end of the response head |
| `content_timeout` | 60 s | the wait between two reads of content |
| `write_timeout` | 60 s | one write to the server |
| `request_timeout` | 300 s | the whole request, redirects and content included |

A response content that stalls longer than `content_timeout` raises `http.ContentError` with
`context.reason = "timeout"`, as the server does for a request content. The other timeouts raise
`core.DeadlineExceededError`, `request_timeout` included when it expires during the content.

`request_timeout` can be set for one request in its options. A streaming download that legitimately lasts
longer than five minutes needs a larger value. A request that is cancelled or fails drops its
connection.

## Handle failures

Errors are core error objects. The ones you will catch:

- `reactor.TransportError`: the connection failed. Its message and `context.attempts` may list
  the addresses a name resolved to. Do not forward them to a peer.
- `core.DeadlineExceededError`: a timeout expired (all but `content_timeout`).
- `net.EndOfStreamError`: the server closed before or inside the response.
- `net.TlsError`: the TLS handshake or verification failed.
- `http.ParseError`: the response is malformed or over a `parser` limit.
- `http.ContentError`: the content is over `max_content` (`context.reason` is `too_large`) or
  stalled longer than `content_timeout` (`timeout`). It carries no `context.status`: a status is
  the server's to give. Escaping an action, it becomes a 500.
- `core.ProtocolError`: a redirect problem or a refused response (101 and upgrades are refused).

> [!WARNING] The client does not filter addresses
> A program that fetches URLs chosen by someone else (webhooks, link previews) must refuse
> private, loopback and link-local addresses itself. A redirect can lead there. Pass
> `redirects = false` and validate each `Location`. The client has no `connect` hook yet (OQ-74).

```lua
local ok, err = pcall(function() return client:get(url):read_json() end)
if not ok then
  if core.is_instance_of(err, core.DeadlineExceededError) then
    -- too slow
  elseif core.is_instance_of(err, http.ContentError) then
    -- too large or stalled: err.context.reason says which
  elseif core.is_instance_of(err, http.ParseError) or core.is_instance_of(err, core.ProtocolError) then
    -- the server answered something that is not valid, or a redirect went
    -- wrong: err.context.reason says which
  else
    error(err, 0) -- a transport or TLS failure, or a bug
  end
end
```

For https, the client trusts the system store and cannot be told to skip verification. See
[Set limits, timeouts and TLS on the HTTP server](http-limits-timeouts-and-tls.md#tls) for the
client options. Not available: HTTP proxies, compression, a cookie jar, HTTP/2, `Retry-After` and retries of
your own (only a request on a pooled connection that died is repeated once, as described above).

## Next steps

- [Handle forms and multipart](handle-forms-and-multipart.md)
- [Set limits, timeouts and TLS on the HTTP server](http-limits-timeouts-and-tls.md)
- [The HTTP model](../explanation/http-model.md)
