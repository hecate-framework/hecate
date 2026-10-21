-- OQ-54: the cost of hostile input for the decoder of hecate.json, and one disagreement of the native decoder.
-- Usage (from the repository root, after `lua tools/run.lua build-native json`):
--   lua docs/spikes/OQ-52/hostile-input.lua time     texts of 16 MiB, valid and broken: CPU time of `decode`
--   lua docs/spikes/OQ-52/hostile-input.lua memory   16 MiB of '[': peak memory of the process (VmHWM)
--   lua docs/spikes/OQ-52/hostile-input.lua literal  a number literal on which yyjson and the reference decoder differ
-- Times are CPU seconds (`os.clock`) of one call; memory is read from /proc/self/status (Linux).
global <const> package, require, print, string, pcall, os, io, tonumber, arg, tostring
package.path = "packages/json/src/?.lua;packages/json/src/?/init.lua;packages/core/src/?.lua;packages/core/src/?/init.lua;"
  .. package.path
package.cpath = ".hecate/rocks/lib/lua/5.5/?.so;" .. package.cpath
local json = require("hecate.json")
local backend = require("hecate.json.internal.backend")

local function reason(err) return err.context and err.context.reason or tostring(err) end

local function peak_megabytes()
  for line in io.lines("/proc/self/status") do
    local kb = line:match("^VmHWM:%s+(%d+)")
    if kb then return tonumber(kb) / 1024 end
  end
end

local mode = arg[1] or "time"
if mode == "time" then
  local function time(label, text)
    local start = os.clock()
    local ok, err = pcall(json.decode, text)
    print(("%-46s %5.2f s  %s"):format(label, os.clock() - start, ok and "decoded" or reason(err)))
  end
  -- 16 MiB minus a few bytes: just under the default max_size
  local body = "[" .. string.rep("1,", 8 * 1024 * 1024 - 2) .. "1]"
  time("array of ones, valid", body)
  time("same, with a trailing comma", body:sub(1, -2) .. ",]")
  time("same, an invalid byte at the end", body:sub(1, -2) .. "x]")
elseif mode == "memory" then
  local text = string.rep("[", 16 * 1024 * 1024)
  local before = peak_megabytes()
  local start = os.clock()
  local _, err = pcall(json.decode, text)
  print(("%d MiB of '[': peak memory %.0f MB before, %.0f MB after; %.2f s; %s"):format(
    #text // 1048576, before, peak_megabytes(), os.clock() - start, reason(err)))
else
  local head = "1.00000000000000011102230246251565404236316680908203125" -- exactly 1 + 2^-53, a tie between two doubles
  for zeros = 0, 1200 do
    local text = "[" .. head .. string.rep("0", zeros) .. "0]"
    backend.use("native")
    local native = json.decode(text)[1]
    backend.use("reference")
    local reference = json.decode(text)[1]
    if native ~= reference then
      print(("%s followed by %d zeros (%d characters): yyjson %.17g, reference %.17g (the correct one)"):format(
        head, zeros + 1, #head + zeros + 1, native, reference))
      return
    end
  end
  print("no difference found")
end
