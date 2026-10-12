local test = require("harness.test")
local commitmsg = require("lib.commitmsg")
local T = test.Case("CommitMsgTest")

function T:test_valid_scoped() self:assert_equal(0, #commitmsg.check("feat(router): add radix tree\n\nbody")) end
function T:test_valid_unscoped_breaking() self:assert_equal(0, #commitmsg.check("fix!: drop old api")) end
function T:test_skips_comments() self:assert_equal(0, #commitmsg.check("# c\n\ndocs(website): x")) end
function T:test_merge_allowed() self:assert_equal(0, #commitmsg.check("Merge branch 'main'")) end
function T:test_unknown_type() self:assert_equal(1, #commitmsg.check("wip(core): x")) end
function T:test_free_text() self:assert_equal(1, #commitmsg.check("update stuff")) end
function T:test_empty_scope() self:assert_equal(1, #commitmsg.check("feat(): x")) end
function T:test_empty_message() self:assert_equal(1, #commitmsg.check("# only comment\n")) end
return T
