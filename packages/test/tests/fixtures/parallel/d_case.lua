local test = require("hecate.test")
local here = debug.getinfo(1, "S").source:sub(2):gsub("\\", "/"):match("^(.*)/[^/]*$") or "."
local T = test.Case("ParallelD")
function T:test_covered() self:assert_equal("positive", dofile(here .. "/../coverage/sample.lua").pick(1)) end
return require("hecate.core").finalise(T)
