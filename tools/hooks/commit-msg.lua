-- commit-msg hook body: arg[1] is the path of the message file written by git.
local script = arg[0]:gsub("\\", "/")
local hooks_dir = script:match("^(.*)/[^/]*$") or "."
package.path = hooks_dir .. "/../?.lua;" .. hooks_dir .. "/../lib/?.lua;" .. package.path
local commitmsg = require("lib.commitmsg")

local f = io.open(arg[1] or "", "rb")
if not f then io.stderr:write("commit-msg: cannot read message file\n") os.exit(1) end
local message = f:read("a")
f:close()
local problems = commitmsg.check(message)
for _, p in ipairs(problems) do io.stderr:write("commit-msg: ", p, "\n") end
os.exit(#problems == 0 and 0 or 1)
