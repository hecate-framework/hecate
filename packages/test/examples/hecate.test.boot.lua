-- Boot an application for a test: replace a service by a fake, send requests
-- without a socket, and see which routes the test never reached.
local reactor = require("hecate.reactor")
local kernel = require("hecate.kernel")
local test = require("hecate.test")

local routes = kernel.routes("greetings")
routes:get("/greeting", {
  name = "show_greeting",
  action = function(request)
    return { text = request.services:resolve("greeter") }
  end,
})
routes:delete("/greeting", {
  name = "delete_greeting",
  action = function() return { deleted = true } end,
})

local options = {
  routes = { routes },
  modules = { {
    name = "greetings",
    services = function(c)
      c:bind("greeter", function() return "hello" end,
        { lifetime = "singleton" })
    end,
  } },
}

reactor.run(function()
  -- The override is applied after every module has bound its services.
  local client, _, coverage = test.boot(options, {
    { key = "greeter", value = "fake" },
  })
  local response = client:get("/greeting")
  print(response.status, response:read_content())
  -- Prints: 200	{"text":"fake"}
  print(client:get("/nowhere").status)
  -- Prints: 404
  print(coverage:report())
  -- Prints: 1 of 2 routes exercised
  -- not exercised: delete_greeting
end)
