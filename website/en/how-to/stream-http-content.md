---
description: Read request content chunk by chunk, stream a response with a function, and know how the server frames, bounds and drains content.
hecate: "0.x"
lua: "5.5"
order: 9
---

# Stream HTTP content

This guide shows how to read the content of a request, and write the content of a response, without holding it all
in memory. It is written for hecate 0.x and Lua 5.5, and assumes you know [how to serve HTTP](serve-http.md).

Streaming relies on [back-pressure](../reference/glossary.md#concurrency): a producer suspends while its consumer is
slower, instead of buffering without bound. On the server it works in both directions:

- A client that sends faster than your action reads waits in the kernel buffers.
- A client that reads more slowly than your action writes makes the write suspend.

## Read the content of a request

The server reads the content of a request only when the action asks for it. There are two ways to ask.

`request:read_content(limit?)` returns the whole content as a string:

```lua
local body = request:read_content(64 * 1024)
```

The content is bounded by the `max_content` option of the server (1 MiB by default), and by `limit` when that is
lower. Content over the bound raises a `ContentError` with status 413. When the request declares a `Content-Length`
over `max_content`, the action does not even run.

`request:stream_content()` returns a `ContentStream`, which you read chunk by chunk. Its `read()` returns the next
chunk, and `nil` after the last one:

```lua
local stream = request:stream_content()
local size = 0
while true do
  local chunk = stream:read()
  if chunk == nil then break end
  size = size + #chunk
end
```

A `ContentStream` also has `read_all(limit?)`, which collects the rest, and `is_finished()`, which tells whether
the end was reached. The stream of a request is bounded by `max_content` too.

### What happens to content the action does not read

What the action leaves unread is drained after the response, so that the next request on the connection can be
parsed. The drain reads up to `max_content`, within `drain_timeout` (5 seconds).

A client may send `Expect: 100-continue` and wait before it sends the content. The server answers `100 Continue`
when the action first reads. If the action answers without reading, the content was never asked for. The server
then closes the connection after its answer, and the client must open a new one.

## Stream a response

Give `content` a function. It receives two functions, `write` and `flush`:

- each `write(data)` sends a chunk;
- `flush()` pushes what was written to the client at once.

<!-- example: packages/http/examples/hecate.http.Response.stream.lua -->
```lua
-- Streaming a response. The content is a function: each `write` is sent as
-- it is called and `flush` pushes it to the client at once. The client
-- reads it chunk by chunk.
local reactor = require("hecate.reactor")
local http = require("hecate.http")

local function action()
  return http.Response(200, {
    fields = http.Fields({ ["Content-Type"] = "text/plain" }),
    content = function(write, flush)
      for i = 1, 3 do
        write(("line %d\n"):format(i))
        flush()
        reactor.sleep(0.01)
      end
    end,
  })
end

reactor.run(function()
  local server = http.Server(action, { port = 0 })
  local listener = server:listen()
  local serving = reactor.fork(server.serve, server, listener)
  local client <close> = http.Client()
  local response <close> = client:get("http://127.0.0.1:" .. listener:local_address().port .. "/")
  print(response.fields:get("Transfer-Encoding"))
  -- Prints: chunked
  local stream, text = response:stream_content(), {}
  while true do
    local chunk = stream:read()
    if chunk == nil then break end
    text[#text + 1] = chunk:gsub("\n", "|")
  end
  print(table.concat(text))
  -- Prints: line 1|line 2|line 3|
  server:shutdown()
  reactor.join(serving)
end)
```

The framing of the content depends on what you declared:

| You declared | The server sends |
|---|---|
| no `Content-Length` | the content with the chunked transfer coding |
| a `Content-Length` field | the raw bytes; you must write exactly that many |
| nothing, to an HTTP/1.0 client | the content, which ends when the connection closes |

### A slow reader

The function runs inside the [scope](../reference/glossary.md#concurrency) of the request. The `write` call
suspends while the client is slow.

`write_timeout` (60 seconds) bounds one write. It closes the connection of a reader that never reads, and the
writing action then gets a `DeadlineExceededError`.

> [!WARNING] A disconnected client is not detected yet
> While your action runs, nothing reads the connection. A client that left is noticed only at the next write, which
> fails. A long computation keeps running until then (OQ-70).

## See also

- [Handle forms and multipart](handle-forms-and-multipart.md)
- [Set limits, timeouts and TLS on the HTTP server](http-limits-timeouts-and-tls.md)
- [The HTTP model](../explanation/http-model.md)
