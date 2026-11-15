-- A long case name in a nested directory: the name is shortened to fit the width, and the path (with backslashes
-- on Windows) is discovered and loaded.
local test = require("hecate.test")
local T = test.Case("ACaseWithARatherLongNameToCheckHowNamesAreShortenedOnANarrowTerminal")

function T:test_one() self:assert_true(true) end
function T:test_two() self:assert_true(true) end

return require("hecate.core").finalise(T)
