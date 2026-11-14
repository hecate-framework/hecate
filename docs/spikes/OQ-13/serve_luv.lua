local uv = require("luv")
local h = uv.spawn("sleep", {args = {"30"}, stdio = {0, 1, 2}}, function(code, sig) print("child exit", code, sig); os.exit(0) end)
local s = uv.new_signal(); s:start("sigterm", function() print("forwarding SIGTERM"); h:kill("sigterm") end)
uv.run()
