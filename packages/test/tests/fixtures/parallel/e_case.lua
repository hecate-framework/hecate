local reactor = require("hecate.reactor")
-- a worker that sends something that is not a message of the protocol, then ends
reactor.run(function() require("hecate.reactor.ipc").parent():send("{not json") end)
os.exit(0)
