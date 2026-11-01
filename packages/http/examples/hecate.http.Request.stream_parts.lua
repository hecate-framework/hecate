-- A handler that reads a multipart upload part by part. The file is never trusted with its
-- name: the handler keeps its own and only counts the bytes.
local reactor = require("hecate.reactor")
local http = require("hecate.http")

local function handler(request)
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
  local server = http.Server(handler, { port = 0 })
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
  server:shutdown()
  reactor.join(serving)
end)
-- Prints: title=report; upload: 100 bytes (client name passwd)
