local test = require("harness.test")
local reactor = require("hecate.reactor")
local log = require("hecate.log")
local T = test.Case("ContextPropagationTest")

-- A logger value captured by the forked closure carries its context across fork and join.
function T:test_a_child_logger_carries_its_context_into_forked_computations()
  local sink = log.MemorySink()
  local logger = log.Logger({ sinks = { sink }, clock = function() return 0 end })
  reactor.Reactor({ clock = "virtual" }):run(function()
    local request = logger:with_context({ request_id = "r1" })
    reactor.scope(function()
      reactor.fork(function() reactor.sleep(2); request:informational("slow") end)
      reactor.fork(function() reactor.sleep(1); request:informational("fast") end)
    end)
    request:informational("joined")
  end)
  local records = sink:records()
  self:assert_equal(3, #records)
  self:assert_equal("fast", records[1].message)
  for _, record in ipairs(records) do self:assert_equal("r1", record.context.request_id) end
end

function T:test_bound_fields_reach_forked_and_detached_computations()
  local sink = log.MemorySink()
  local logger = log.Logger({ sinks = { sink }, clock = function() return 0 end })
  reactor.Reactor({ clock = "virtual" }):run(function()
    log.bind({ request_id = "r3" }, function()
      reactor.scope(function()
        reactor.fork(function() reactor.sleep(1); logger:informational("forked") end)
        reactor.detach(function() reactor.sleep(2); logger:informational("detached") end)
      end)
      logger:informational("body")
    end)
    logger:informational("outside")
  end)
  local by_message = {}
  for _, record in ipairs(sink:records()) do by_message[record.message] = record end
  self:assert_equal("r3", by_message.forked.context.request_id)
  self:assert_equal("r3", by_message.detached.context.request_id)
  self:assert_equal("r3", by_message.body.context.request_id)
  self:assert_nil(by_message.outside.context.request_id)
end

function T:test_nested_bind_merges_and_logger_context_wins()
  local sink = log.MemorySink()
  local logger = log.Logger({ sinks = { sink }, context = { service = "api" } })
  reactor.Reactor({ clock = "virtual" }):run(function()
    log.bind({ request_id = "a", service = "ignored" }, function()
      log.bind({ user = "u" }, function() logger:informational("x") end)
    end)
  end)
  local context = sink:records()[1].context
  self:assert_equal("a", context.request_id)
  self:assert_equal("u", context.user)
  self:assert_equal("api", context.service)
end

function T:test_logging_outside_a_reactor_has_no_ambient_context()
  local sink = log.MemorySink()
  local logger = log.Logger({ sinks = { sink } })
  logger:informational("x")
  self:assert_equal(0, logger:failures())
  self:assert_nil(sink:records()[1].context.request_id)
end

function T:test_logging_does_not_suspend_the_caller()
  local sink = log.MemorySink()
  local logger = log.Logger({ sinks = { sink } })
  local order = {}
  reactor.Reactor({ clock = "virtual" }):run(function()
    reactor.scope(function()
      reactor.fork(function() order[#order + 1] = "other" end)
      logger:informational("x")
      order[#order + 1] = "caller"
    end)
  end)
  self:assert_equal("caller,other", table.concat(order, ","))
  self:assert_equal(1, #sink:records())
end

function T:test_a_context_provider_can_read_a_value_set_by_the_running_computation()
  local sink = log.MemorySink()
  local current
  local logger = log.Logger({ sinks = { sink }, context_provider = function() return current end })
  reactor.Reactor({ clock = "virtual" }):run(function()
    current = { request_id = "r2" }
    reactor.scope(function() reactor.fork(function() logger:informational("x") end) end)
  end)
  self:assert_equal("r2", sink:records()[1].context.request_id)
end

return T
