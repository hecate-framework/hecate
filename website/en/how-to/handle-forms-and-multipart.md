---
description: Read urlencoded forms and multipart uploads in an action, never trust a client filename, and send forms and multipart messages with the client.
hecate: "0.x"
lua: "5.5"
order: 11
---

# Handle forms and multipart

This guide shows how to read `application/x-www-form-urlencoded` and `multipart/form-data` content in an
[action](../reference/glossary.md#object-model-and-architecture), the function that serves a request. It also shows
how to send both with the client. It is written for hecate 0.x and Lua 5.5, and assumes you know
[how to serve HTTP](serve-http.md).

The form parsers are pure Lua. They need no native module.

## Read a urlencoded form

`request:read_form(limits?)` reads the content and returns a `Form`. A `Form` has these methods, and its names can
repeat:

- `get(name)`, the first value, or `nil`;
- `get_all(name)`, every value, in order;
- `count()` and `pairs()`.

<!-- example: packages/http/examples/hecate.http.Request.read_form.lua -->
```lua
-- An action that reads a urlencoded form. The client sends pairs with
-- `form`; a name that repeats keeps its order.
local reactor = require("hecate.reactor")
local http = require("hecate.http")

local function action(request)
  local form = request:read_form({ max_pairs = 50 })
  local tags = table.concat(form:get_all("tag"), ",")
  return http.Response(200, { content = form:get("name") .. " " .. tags })
end

reactor.run(function()
  local server = http.Server(action, { port = 0 })
  local listener = server:listen()
  local serving = reactor.fork(server.serve, server, listener)
  local url = "http://127.0.0.1:" .. listener:local_address().port .. "/"
  local client <close> = http.Client()
  local response = client:post(url, nil, {
    form = { { "name", "Ada Lovelace" }, { "tag", "math" }, { "tag", "code" } },
  })
  print(response:read_content())
  -- Prints: Ada Lovelace math,code
  server:shutdown()
  reactor.join(serving)
end)
```

`read_form` raises a `FormError` with status 415 when the `Content-Type` is not urlencoded.

### Limits

The limits of a form are `max_pairs` (1000) and `max_size` (1 MiB). Over either, the form is refused with a 413.

The `max_content` of the server applies first (1 MiB by default). A larger form is a 413 `ContentError` while it is
read, and `limits.max_size` can only lower that bound.

### What the parser accepts

The parser is strict by choice. These inputs are refused with a 400 instead of being guessed at:

- a malformed percent sequence (`%`, `%4`, `%zz`);
- text that is not valid UTF-8;
- a NUL byte.

`+` is a space, `%XX` is a byte, and the first `=` splits a name from its value. Empty pairs between `&` are skipped.

To build the text yourself, use `http.form.encode_urlencoded(pairs)`. To parse a string without a request, use
`http.form.parse_urlencoded(text, limits?)`.

## Read a multipart upload

`request:stream_parts(limits?)` returns a reader. `reader:next_part()` suspends until the next part is ready, then
returns a `Part`, or `nil` after the last one.

A part has:

- `name`, `filename` and `content_type`;
- `fields`, its own `Fields`;
- `read_content(limit?)` and `stream_content()`;
- `safe_filename()`.

<!-- example: packages/http/examples/hecate.http.Request.stream_parts.lua -->
```lua
-- An action that reads a multipart upload part by part. The file is never
-- trusted with its name: the action keeps its own and only counts the bytes.
local reactor = require("hecate.reactor")
local http = require("hecate.http")

local function action(request)
  local reader = request:stream_parts({ max_part_size = 1024 * 1024 })
  local seen = {}
  while true do
    local part = reader:next_part()
    if part == nil then break end
    if part.filename ~= nil then
      local size = 0
      local stream = part:stream_content()
      while true do
        local chunk = stream:read()
        if chunk == nil then break end
        size = size + #chunk
      end
      seen[#seen + 1] = ("%s: %d bytes (client name %s)"):format(part.name, size, tostring(part:safe_filename()))
    else
      seen[#seen + 1] = part.name .. "=" .. part:read_content()
    end
  end
  return http.Response(200, { content = table.concat(seen, "; ") })
end

reactor.run(function()
  local server = http.Server(action, { port = 0 })
  local listener = server:listen()
  local serving = reactor.fork(server.serve, server, listener)
  local url = "http://127.0.0.1:" .. listener:local_address().port .. "/"
  local client <close> = http.Client()
  local response = client:post(url, nil, {
    multipart = {
      { name = "title", content = "report" },
      { name = "upload", filename = "../../etc/passwd", content_type = "text/plain", content = ("x"):rep(100) },
    },
  })
  print(response:read_content())
  -- Prints: title=report; upload: 100 bytes (client name passwd)
  server:shutdown()
  reactor.join(serving)
end)
```

The reader pulls content only when it needs it. It keeps one chunk, the header fields of the current part, and the
tail of a possible delimiter. A part you leave unread is skipped, within `max_part_size`. Parts arrive in order, and
duplicate names are delivered in order too.

### Limits

| Limit | Default | When exceeded |
|---|---|---|
| `max_parts` | 100 | 413 |
| `max_part_fields_size` | 8192 bytes | 413 |
| `max_part_size` | 1 MiB | 413 (`ContentError`) |
| `max_total_size` | 1 MiB | 413 |

The `max_content` of the server bounds the whole message first. Raise both when you accept larger uploads.

### Never trust a client filename

> [!WARNING] Never use a client filename as a path
> `part.filename` is the raw value the client sent. Store the file under a name you generate, and keep the client's
> name as data. No code of `hecate.http` opens a file by a client name.

`part:safe_filename()` reduces the filename to a conservative base name:

- it removes the directories (`/` and `\`), the control characters and the characters `< > : " | ? *`;
- it removes leading dots, and trailing dots and spaces;
- it cuts the name to 255 bytes, never inside a UTF-8 character;
- it returns `nil` for a Windows device name (`CON`, `PRN`, `AUX`, `NUL`, `COM1` to `COM9`, `LPT1` to `LPT9`, with or
  without an extension), and when nothing is left.

The result is still the client's choice. It reduces the risk of a path trick; it does not make the name trustworthy.

### What the reader does not parse

- A nested `multipart/mixed` is not parsed: it arrives as one part, with the inner message as its content.
- `Content-Transfer-Encoding` is ignored.

## Refusals

A `FormError` carries `context.reason` and `context.status`. In an action you can let it escape: the server answers
with [problem details](../reference/glossary.md#http) that echo nothing of the input.

| Reason | Status |
|---|---|
| `unsupported_media_type` | 415 |
| `bad_boundary`, `bad_part_fields`, `missing_name`, `truncated` | 400 |
| `too_many_parts`, `part_fields_too_large`, `total_too_large` | 413 |
| `bad_percent_encoding`, `invalid_utf8`, `nul_in_value` | 400 |
| `too_many_pairs`, `too_large` | 413 |

## Send forms and multipart with the client

Pass `form` to send urlencoded content. It is a list of `{ name, value }` pairs.

```lua
client:post(url, nil, { form = { { "q", "lua 5.5" }, { "page", "2" } } })
```

Pass `multipart` to send `multipart/form-data`. Each part is `{ name, filename?, content_type?, content }`, and
`content` is a string or a function that streams.

```lua
client:post(url, nil, {
  multipart = {
    { name = "title", content = "report" },
    { name = "upload", filename = "data.csv", content_type = "text/csv",
      content = function(write) write("a,b\n"); write("1,2\n") end },
  },
})
```

The boundary is random. The framing depends on the parts:

- With only string parts, the message is sent with `Content-Length`, and it can be replayed.
- With a function part, it is streamed with the chunked coding.

## See also

- [Stream HTTP content](stream-http-content.md)
- [Set limits, timeouts and TLS on the HTTP server](http-limits-timeouts-and-tls.md)
- [The HTTP model](../explanation/http-model.md)
