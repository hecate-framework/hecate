-- A Unix-domain socket (a named pipe on Windows) in place of TCP: the stream and the buffered
-- API are the same. The path must not exist; `mode` says who may connect (default: the owner).
local reactor = require("hecate.reactor")
local net = require("hecate.net")

local WINDOWS = package.config:sub(1, 1) == "\\"
local name = ("hecate-example-%x-%d"):format(os.time(), math.random(0, 1 << 30))
local path = WINDOWS and ("\\\\.\\pipe\\" .. name) or ((os.getenv("TMPDIR") or "/tmp") .. "/" .. name .. ".sock")

reactor.run(function()
  local listener <close> = net.listen_pipe(path, { mode = "owner" })
  reactor.fork(function()
    local peer <close> = listener:accept()
    local reader, writer = peer:reader(), peer:writer()
    writer:write(reader:read_line():upper() .. "\n")
    writer:flush()
  end)
  local client <close> = net.connect_pipe(path)
  local reader, writer = client:reader(), client:writer()
  writer:write("hello\n")
  writer:flush()
  print(reader:read_line())
end)
-- Prints: HELLO
