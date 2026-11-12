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
  end)
  reactor.select(signalled, finished)
  server:shutdown(10)
  reactor.join(serving)
end)
-- Prints: hello
