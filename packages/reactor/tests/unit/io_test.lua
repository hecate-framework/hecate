local test = require("harness.test")
local core = require("hecate.core")
local reactor = require("hecate.reactor")
local uv = require("luv")
local T = test.Case("IoTest")

local function tmp(name) return uv.os_tmpdir() .. "/hecate-reactor-" .. uv.os_getpid() .. "-" .. name end

function T:test_detach_outlives_the_calling_scope_and_its_failure_is_isolated()
  local log = {}
  reactor.run(function()
    local detached
    reactor.scope(function()
      detached = reactor.detach(function()
        reactor.sleep(0.02)
        log[#log + 1] = "detached"
        error(core.Error("boom"))
      end)
    end)
    log[#log + 1] = "scope ended"
    self:assert_error(function() detached:value() end)
  end)
  self:assert_equal("scope ended,detached", table.concat(log, ","))
end

function T:test_fs_round_trip_and_stat()
  local path = tmp("file")
  local content = reactor.run(function()
    reactor.fs.write_file(path, "héllo")
    local info = reactor.fs.stat(path)
    self:assert_equal("file", info.type)
    local data = reactor.fs.read_file(path)
    reactor.fs.remove(path)
    self:assert_equal(nil, reactor.fs.stat(path))
    return data
  end)
  self:assert_equal("héllo", content)
end

function T:test_fs_missing_file_raises_io_error()
  local err = self:assert_error(function()
    reactor.run(function() reactor.fs.read_file(tmp("absent")) end)
  end)
  self:assert_true(core.is_instance_of(err, reactor.IoError))
  self:assert_equal("ENOENT", err.context.errno)
end

function T:test_fs_list_directory()
  local dir = tmp("dir")
  local names = reactor.run(function()
    reactor.fs.mkdir(dir)
    reactor.fs.write_file(dir .. "/a", "1")
    local entries = reactor.fs.list(dir)
    reactor.fs.remove(dir .. "/a")
    reactor.fs.rmdir(dir)
    return entries
  end)
  self:assert_equal(1, #names)
  self:assert_equal("a", names[1].name)
end

function T:test_fs_requires_a_managed_coroutine()
  local err = self:assert_error(function() reactor.fs.read_file("x") end)
  self:assert_true(core.is_instance_of(err, core.NonYieldableContextError))
end

function T:test_wait_signal_returns_the_name()
  if uv.os_uname().sysname:match("Windows") then return end
  local name = reactor.run(function()
    reactor.fork(function() reactor.sleep(0.02); uv.kill(uv.os_getpid(), "sigusr1") end)
    return reactor.wait_signal("sigusr1")
  end)
  self:assert_equal("sigusr1", name)
end

function T:test_wait_signal_is_cancellable_and_closes_its_handle()
  local before = reactor.Reactor.open_handles()
  reactor.run(function()
    local ok = pcall(reactor.deadline, 0.02, reactor.wait_signal, "sigusr2")
    self:assert_false(ok)
  end)
  self:assert_equal(before, reactor.Reactor.open_handles())
end

function T:test_run_process_captures_output_and_status()
  local lua = uv.exepath()
  local result = reactor.run(function()
    return reactor.run_process(lua, { "-e", "io.write('out') io.stderr:write('err') os.exit(3)" })
  end)
  self:assert_equal(3, result.code)
  self:assert_equal("out", result.stdout)
  self:assert_equal("err", result.stderr)
end

function T:test_run_process_unknown_program_raises_io_error()
  local err = self:assert_error(function()
    reactor.run(function() reactor.run_process("hecate-no-such-program-xyz") end)
  end)
  self:assert_true(core.is_instance_of(err, reactor.IoError))
end

function T:test_io_on_a_virtual_clock_is_refused()
  local err = self:assert_error(function()
    reactor.Reactor({ clock = "virtual" }):run(function() reactor.fs.read_file("x") end)
  end)
  self:assert_true(core.is_instance_of(err, core.Error))
end

return T
