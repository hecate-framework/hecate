-- Runs one *_test.lua file and prints TAP lines. Usage: lua run_file.lua <file> <src-path>...
local harness_dir = arg[0]:gsub("\\", "/"):match("^(.*)/[^/]*$") or "."
package.path = harness_dir .. "/?.lua;" .. package.path
local test = require("test")
-- Project-local LuaRocks trees (native rocks such as luv): `.hecate/rocks` is where CI and
-- developers install them; `spikes/rocks` is the cloud-session spike tree.
do
  local root = harness_dir .. "/../.."
  local version = _VERSION:match("%d+%.%d+")
  for _, tree in ipairs({ "/.hecate/rocks", "/spikes/rocks" }) do
    local base = root .. tree
    package.path = base .. "/share/lua/" .. version .. "/?.lua;" .. base .. "/share/lua/" .. version
      .. "/?/init.lua;" .. package.path
    package.cpath = base .. "/lib/lua/" .. version .. "/?.so;" .. base .. "/lib/lua/" .. version
      .. "/?.dll;" .. package.cpath
  end
end
local file = arg[1]
for i = 2, #arg do package.path = arg[i] .. "/?.lua;" .. arg[i] .. "/?/init.lua;" .. package.path end
local class = assert(loadfile(file))()
local failed = 0
for i, r in ipairs(test.run_case(class)) do
  if r.ok then print(("ok %d - %s"):format(i, r.name))
  else
    failed = failed + 1
    print(("not ok %d - %s"):format(i, r.name))
    print("  # " .. tostring(r.message):gsub("\n", "\n  # "))
  end
end
os.exit(failed == 0 and 0 or 1)
