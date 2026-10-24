local test = require("harness.test")
local json = require("hecate.json")
local log = require("hecate.log")
local T = test.Case("FileSinkTest")

local function read(path)
  local handle = assert(io.open(path, "rb"))
  local text = handle:read("a")
  handle:close()
  return text
end

function T:test_records_are_appended_as_json_lines()
  local path = os.tmpname()
  local sink = log.FileSink({ path = path })
  local logger = log.Logger({ sinks = { sink }, clock = function() return 1000000000 end })
  logger:error("one")
  sink:close()
  local again = log.FileSink({ path = path })
  log.Logger({ sinks = { again } }):error("two")
  again:close()
  local lines = {}
  for line in read(path):gmatch("[^\n]+") do lines[#lines + 1] = json.decode(line) end
  os.remove(path)
  self:assert_equal(2, #lines)
  self:assert_equal("one", lines[1].message)
  self:assert_equal("two", lines[2].message)
end

function T:test_writes_after_close_are_ignored()
  local path = os.tmpname()
  local sink = log.FileSink({ path = path })
  sink:close()
  log.Logger({ sinks = { sink } }):error("late")
  local text = read(path)
  os.remove(path)
  self:assert_equal("", text)
end

function T:test_an_unopenable_path_raises()
  self:assert_error(function() log.FileSink({ path = "/nonexistent-dir/x/log" }) end)
  self:assert_error(function() log.FileSink({}) end)
end

function T:test_a_failed_write_raises_and_the_logger_counts_it()
  -- Portable: the file handle is replaced by one whose write reports a full disk, as `file:write` does.
  local real_open = io.open
  local closed = false
  local fake = {
    setvbuf = function() return true end,
    write = function() return nil, "no space left on device", 28 end,
    close = function() closed = true return true end,
  }
  ---@diagnostic disable-next-line: duplicate-set-field, assign-type-mismatch
  io.open = function() return fake end
  local ok, sink = pcall(function() return log.FileSink({ path = "unused.log" }) end)
  io.open = real_open
  self:assert_true(ok, "the sink could not be created")
  local logger = log.Logger({ sinks = { sink } })
  logger:informational("x")
  self:assert_equal(1, logger:failures())
  local raised, err = pcall(sink.write, sink, log.Record(log.Severity.informational, "y", {}, {}, 0))
  self:assert_true(not raised)
  self:assert_not_nil(tostring(err):find("no space left on device", 1, true))
  sink:close()
  self:assert_true(closed)
end

return T
