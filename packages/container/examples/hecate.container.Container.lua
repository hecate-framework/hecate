-- Bind services, validate the graph at boot, then resolve them: a singleton
-- is shared, a scoped service lives in one service scope (one per request), a
-- transient is built for each caller.
local core = require("hecate.core")
local container = require("hecate.container")

local Clock = core.class("Clock")
function Clock:now() return 1700000000 end
core.finalise(Clock)

local Session = core.class("Session")
function Session:init(clock) self.opened_at = clock:now() end
function Session:__close() self.closed = true end
core.finalise(Session)

local c = container.Container()
c:bind("clock", Clock, { lifetime = "singleton" })
c:bind("session", Session, { lifetime = "scoped", requires = { "clock" } })
c:validate()

local session
do
  local request <close> = c:open_scope()
  session = request:resolve("session")
  print(session == request:resolve("session"))
  -- Prints: true
  print(c:open_scope():resolve("session") == session)
  -- Prints: false
  print(c:resolve("clock") == request:resolve("clock"))
  -- Prints: true
end
-- Closing the scope closes its scoped services.
print(session.closed)
-- Prints: true

-- A mistake in the composition is found at boot, with every problem at once.
local broken = container.Container()
broken:bind("a", function() end, { lifetime = "transient", requires = { "b" } })
broken:bind("b", function() end, { lifetime = "transient", requires = { "a", "missing" } })
local ok, err = pcall(function() broken:validate() end)
---@cast err hecate.container.GraphError
print(ok, err.context.problems[1].context.path[1], #err.context.problems)
-- Prints: false	a	2
