-- An asynchronous sink queues records and writes them from a drain computation: logging never waits
-- for the target. `close` flushes what is queued and stops the coroutine.
local reactor = require("hecate.reactor")
local log = require("hecate.log")

reactor.run(function()
  local memory = log.MemorySink()
  local async = log.AsyncSink({ sink = memory, capacity = 128 })
  local logger = log.Logger({ sinks = { async } })

  logger:informational("first")
  logger:informational("second")
  local waiting = async:pending()
  async:close()
  print(("%d %d %d"):format(waiting, #memory:records(), async:dropped()))
end)
-- Prints: 2 2 0
