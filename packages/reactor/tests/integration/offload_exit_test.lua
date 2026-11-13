-- A program whose offloaded function outlives its cancelled caller exits cleanly: `Reactor:run` waits for
-- the function before returning, because luv crashes when the Lua state closes with work in flight
-- (concurrency.md, "Offload").
local test = require("harness.test")
local uv = require("luv")
local reactor = require("hecate.reactor")
local T = test.Case("OffloadExitTest")

local here = debug.getinfo(1, "S").source:sub(2):match("^(.*)[/\\]integration[/\\][^/\\]+$") or "."
local child_script = uv.fs_realpath(here .. "/fixtures/offload_exit_child.lua") or here .. "/fixtures/offload_exit_child.lua"

--- Makes the relative entries of a search path absolute.
local function absolute(search_path)
  local entries = {}
  for entry in search_path:gmatch("[^;]+") do
    local absolute_entry = entry
    if not (entry:match("^[/\\]") or entry:match("^%a:") or entry:match("^!")) then
      absolute_entry = uv.cwd() .. "/" .. entry
    end
    entries[#entries + 1] = absolute_entry
  end
  return table.concat(entries, ";")
end

function T:test_a_program_exits_cleanly_after_a_cancelled_offload()
  local setup = ("package.path = %q; package.cpath = %q"):format(absolute(package.path), absolute(package.cpath))
  for _ = 1, 3 do
    local result = reactor.run(function()
      return reactor.run_process(uv.exepath(), { "-e", setup, child_script })
    end)
    self:assert_equal("released", result.stdout, result.stderr)
    self:assert_equal(0, result.code, ("the child exited with code %s, signal %s: %s"):format(result.code, result.signal, result.stderr))
    self:assert_equal(0, result.signal)
  end
end

function T:test_an_offloaded_function_requires_a_module_through_lua_path()
  local fixtures = here .. "/fixtures"
  local search = absolute(fixtures .. "/?.lua") .. ";;" -- ";;": the default path after it
  local setup = ("package.path = %q; package.cpath = %q"):format(absolute(package.path), absolute(package.cpath))
  local script = uv.fs_realpath(fixtures .. "/offload_require_child.lua") or fixtures .. "/offload_require_child.lua"
  local status = reactor.run(function()
    -- Both names: a pool thread's state reads LUA_PATH_5_5 first, then LUA_PATH.
    local child = reactor.spawn(uv.exepath(), { "-e", setup, script },
      { env = { LUA_PATH = search, LUA_PATH_5_5 = search }, stdout = "ignore" })
    return child:wait()
  end)
  self:assert_equal(0, status.code, ("the child exited with code %s, signal %s"):format(status.code, status.signal))
end

return T
