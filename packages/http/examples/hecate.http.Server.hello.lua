-- The smallest server: it listens on 127.0.0.1:8080 and answers every
-- request with "hello".
local http, reactor = require("hecate.http"), require("hecate.reactor")
local function action() return http.Response(200, { content = "hello\n" }) end
reactor.run(function() http.Server(action, { port = 8080 }):serve() end)
-- Answers: hello
