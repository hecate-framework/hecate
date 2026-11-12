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

return T
