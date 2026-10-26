local test = require("harness.test")
local glossary = require("lib.glossary")
local T = test.Case("GlossaryTest")

function T:test_words() self:assert_equal(3, #glossary.words("greenThread_pool")) end
function T:test_flags_snake_and_camel()
  self:assert_equal(1, #glossary.scan("local green_thread = 1\n"))
  self:assert_equal(1, #glossary.scan("local makePromise = 1\n"))
end
function T:test_ignores_comments_strings_and_exceptions()
  self:assert_equal(0, #glossary.scan('-- a promise\nlocal s = "spawn"\nlocal spawn = 1 -- glossary-ok\n'))
end
function T:test_clean() self:assert_equal(0, #glossary.scan("local f = fork(computation)\n")) end
return T
