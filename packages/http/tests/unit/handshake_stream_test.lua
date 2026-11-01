---@diagnostic disable: missing-fields, param-type-mismatch  -- the tests pass invalid arguments on purpose
local test = require("harness.test")
local core = require("hecate.core")
local reactor = require("hecate.reactor")
local HandshakeStream = require("hecate.http.handshake_stream")
local T = test.Case("HandshakeStreamTest")

--- An in-memory stream: `read` hands out the chunks in turn.
local function memory(chunks)
  local stream = { closed = false, written = {} }
  local i = 0
  function stream:read() i = i + 1; return chunks[i] end
  function stream:write(data) self.written[#self.written + 1] = data end
  function stream:close() self.closed = true end
  function stream:is_closed() return self.closed end
  return stream
end

function T:test_reads_within_the_budget_pass_through_and_are_counted()
  local inner = memory({ "abc", "de" })
  local stream = HandshakeStream(inner, 5)
  reactor.run(function()
    self:assert_equal("abc", stream:read())
    self:assert_equal("de", stream:read())
    self:assert_nil(stream:read())
  end)
  self:assert_equal(5, stream:received())
  self:assert_false(inner.closed)
end

function T:test_more_than_the_budget_closes_the_stream_and_raises_a_protocol_error()
  local inner = memory({ "abc", "def" })
  local stream = HandshakeStream(inner, 5)
  reactor.run(function()
    stream:read()
    local ok, err = pcall(stream.read, stream)
    self:assert_false(ok)
    self:assert_true(core.is_instance_of(err, core.ProtocolError))
    self:assert_equal("handshake_too_large", err.context.reason)
  end)
  self:assert_true(inner.closed)
end

function T:test_release_lifts_the_budget_and_writes_pass_through()
  local inner = memory({ ("x"):rep(100) })
  local stream = HandshakeStream(inner, 5)
  stream:release()
  reactor.run(function()
    self:assert_equal(100, #stream:read())
    stream:write("out")
  end)
  self:assert_equal("out", inner.written[1])
end

function T:test_the_budget_is_a_positive_integer()
  self:assert_error(function() HandshakeStream(memory({}), 0) end)
  self:assert_error(function() HandshakeStream(memory({}), 1.5) end)
end

return T
