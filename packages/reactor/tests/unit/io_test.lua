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
    ---@cast info -nil
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
  self:assert_false(core.is_instance_of(err, core.NetworkError)) -- fs and process failures stay IoError
  self:assert_equal("ENOENT", err.context.errno)
  self:assert_equal("reactor.fs.read_file: ", err.message:sub(1, 22)) -- the call as the caller wrote it
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

function T:test_a_request_that_fails_to_start_raises_instead_of_hanging()
  local uv_call = require("hecate.reactor.internal.uv_call")
  local err = self:assert_error(function()
    reactor.run(function()
      uv_call.request("reactor.fs.stub", "stub x", function() return nil, "EINVAL: x" end) -- never calls back
    end)
  end)
  self:assert_true(core.is_instance_of(err, reactor.IoError), tostring(err))
  self:assert_equal("EINVAL", err.context.errno)
end

function T:test_a_failed_signal_registration_leaves_the_computation_in_a_clean_state()
  reactor.run(function()
    -- An unknown name fails the registration on every platform (libuv refuses SIGKILL on POSIX only: on Windows
    -- that registration succeeds and would wait for a signal that never comes).
    local ok = pcall(reactor.wait_signal, "sigfoo")
    self:assert_false(ok)
    local slept = false
    pcall(reactor.scope, function(scope)
      scope:cancel()
      -- The computation is running: the cancellation must not have scheduled a second resumption.
      reactor.shield(1, function() reactor.sleep(0.01); slept = true end)
    end)
    self:assert_true(slept)
  end)
end

function T:test_fs_rejects_an_embedded_nul_in_a_path()
  ---@diagnostic disable: param-type-mismatch  -- the arguments are invalid on purpose
  reactor.run(function()
    for _, call in ipairs({
      function() reactor.fs.read_file("a\0b") end,
      function() reactor.fs.write_file("a\0b", "x") end,
      function() reactor.fs.stat("a\0b") end,
      function() reactor.fs.remove("a\0b") end,
      function() reactor.fs.mkdir("a\0b") end,
      function() reactor.fs.rmdir("a\0b") end,
      function() reactor.fs.list("a\0b") end,
    }) do
      local err = self:assert_error(call)
      self:assert_true(core.is_instance_of(err, core.ArgumentError), tostring(err))
    end
  end)
end

function T:test_a_failure_to_close_does_not_replace_the_error_of_a_read()
  local directory = tmp("readdir")
  assert(uv.fs_mkdir(directory, 448))
  local close = uv.fs_close
  uv.fs_close = function(fd, callback) return close(fd, function() callback("EIO: close failed") end) end
  local ok, err = pcall(reactor.run, function() reactor.fs.read_file(directory) end)
  uv.fs_close = close
  uv.fs_rmdir(directory)
  self:assert_false(ok)
  self:assert_true(core.is_instance_of(err, reactor.IoError), tostring(err))
  if package.config:sub(1, 1) ~= "\\" then self:assert_equal("EISDIR", err.context.errno) end
end

function T:test_a_failure_to_close_does_not_replace_the_error_of_a_write()
  if not uv.fs_stat("/dev/full") then return end -- Linux: writes fail with ENOSPC
  local close = uv.fs_close
  uv.fs_close = function(fd, callback) return close(fd, function() callback("EIO: close failed") end) end
  local ok, err = pcall(reactor.run, function() reactor.fs.write_file("/dev/full", "x") end)
  uv.fs_close = close
  self:assert_false(ok)
  self:assert_equal("ENOSPC", err.context.errno)
end

function T:test_stat_reports_a_path_below_a_file_as_missing()
  local path = tmp("notdir")
  reactor.run(function()
    reactor.fs.write_file(path, "x")
    self:assert_equal(nil, reactor.fs.stat(path .. "/child")) -- ENOTDIR: the path does not exist
    reactor.fs.remove(path)
  end)
end

function T:test_a_scan_error_raises_instead_of_ending_the_list()
  local dir = tmp("scanfail")
  local next_entry = uv.fs_scandir_next
  local calls = 0
  uv.fs_scandir_next = function()
    calls = calls + 1
    if calls == 1 then return "a", "file" end
    return nil, "EIO: i/o error"
  end
  local ok, err = pcall(reactor.run, function()
    reactor.fs.mkdir(dir)
    local listed, failure = pcall(reactor.fs.list, dir)
    reactor.fs.rmdir(dir)
    if not listed then error(failure, 0) end
  end)
  uv.fs_scandir_next = next_entry
  self:assert_false(ok)
  self:assert_true(core.is_instance_of(err, reactor.IoError), tostring(err))
  self:assert_equal("EIO", err.context.errno)
end

function T:test_fs_requires_a_managed_coroutine()
  local err = self:assert_error(function() reactor.fs.read_file("x") end)
  self:assert_true(core.is_instance_of(err, core.NonYieldableContextError))
end

function T:test_wait_signal_returns_the_name()
  if uv.os_uname().sysname:match("Windows") then return end
  -- The signal is sent again until the waiter returned, so the test does not depend on the waiter
  -- having installed its handler first; the guard keeps an early signal from ending the process.
  local guard = uv.new_signal()
  guard:start("sigusr1", function() end)
  local name = reactor.run(function()
    local done = false
    reactor.fork(function()
      while not done do
        uv.kill(uv.os_getpid(), "sigusr1")
        reactor.sleep(0.005)
      end
    end)
    local received = reactor.wait_signal("sigusr1")
    done = true
    return received
  end)
  guard:close()
  self:assert_equal("sigusr1", name)
end

function T:test_wait_signal_is_cancellable_and_closes_its_handle()
  local before = reactor.Reactor.open_handles()
  reactor.run(function()
    -- Windows delivers only the console signals.
    local name = package.config:sub(1, 1) == "\\" and "sigint" or "sigusr2"
    local ok = pcall(reactor.deadline, 0.02, reactor.wait_signal, name)
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
