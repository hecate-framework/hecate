---
description: Read request content chunk by chunk, stream a response with a function, and know how the server frames, bounds and drains content.
hecate: "0.x"
lua: "5.5"
order: 9
---

# Stream HTTP content

This guide shows how to read the content of a request and write the content of a response
without holding it all in memory. It is written for hecate 0.x and Lua 5.5. It assumes you know
[how to serve HTTP](serve-http.md).

Streaming relies on [back-pressure](../reference/glossary.md#concurrency). A client that sends
faster than your handler reads waits in the kernel buffers. A client that reads more slowly than
your handler writes makes the write suspend.

## Read the content of a request

The server reads the content when the handler asks for it. There are two ways.

`request:read_content(limit?)` returns the whole content as a string. It is bounded by the
`max_content` option of the server (1 MiB by default) and by `limit` when that is lower. Content
over the bound raises a `ContentError` with status 413. When the request declares a
`Content-Length` over the bound, the handler does not even run.

```lua
local body = request:read_content(64 * 1024)
```

`request:stream_content()` returns a `ContentStream`. Call `read()` for the next chunk. It returns
`nil` after the last one. `read_all(limit?)` collects the rest, and `is_finished()` tells whether
the end was reached.

```lua
local stream = request:stream_content()
local size = 0
while true do
  local chunk = stream:read()
  if chunk == nil then break end
  size = size + #chunk
end
```

What the handler leaves unread is drained after the response, up to `max_content` and within
`drain_timeout` (5 seconds), so the next request on the connection can be parsed. A handler that
never reads makes the server close the connection after its answer when the request waited for
`100 Continue`.

## Stream a response

Give `content` a function. It receives `write` and `flush`. Each `write(data)` sends a chunk.
`flush()` pushes what was written to the client at once.

<!-- example: packages/http/examples/hecate.http.Response.stream.lua -->
```lua
-- Streaming a response. The content is a function: each `write` is sent as it is called and
-- `flush` pushes it to the client at once. The client reads it chunk by chunk.
local reactor = require("hecate.reactor")
local http = require("hecate.http")

local function handler()
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
  local server = http.Server(handler, { port = 0 })
  local listener = server:listen()
  local serving = reactor.fork(server.serve, server, listener)
  local client <close> = http.Client()
  local response <close> = client:get("http://127.0.0.1:" .. listener:local_address().port .. "/")
  print(response.fields:get("Transfer-Encoding"))
  local stream, text = response:stream_content(), {}
  while true do
    local chunk = stream:read()
    if chunk == nil then break end
    text[#text + 1] = chunk:gsub("\n", "|")
  end
  print(table.concat(text))
  server:shutdown()
  reactor.join(serving)
end)
-- Prints: chunked
-- line 1|line 2|line 3|
```

The framing depends on what you declared:

- No `Content-Length`: the server uses the chunked transfer coding.
- A `Content-Length` field that you set: the raw bytes are sent, and you must write exactly that
  many.
- An HTTP/1.0 client: the content ends when the connection closes.

The function runs inside the request's scope. The `write` call suspends while the client is slow,
and `write_timeout` (60 seconds) closes the connection of a reader that never reads. The writing
handler then gets a `DeadlineExceededError`.

> [!WARNING] A disconnected client is not detected yet
> While your handler runs, nothing reads the connection. A client that left is noticed at the
> next write, which fails. A long computation keeps running until then (OQ-70).

## Next steps

- [Handle forms and multipart](handle-forms-and-multipart.md)
- [Set limits, timeouts and TLS on the HTTP server](http-limits-timeouts-and-tls.md)
- [The HTTP model](../explanation/http-model.md)
