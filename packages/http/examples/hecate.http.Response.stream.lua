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
