local test = require("harness.test")
local util = require("lib.util")
local T = test.Case("LinkModulesTest")

function T:test_the_packages_are_merged_under_the_hecate_directory_of_the_project()
  local base = util.make_temp_dir(".hecate", "link-modules")
  self:assert_true(base ~= nil)
  local out, ok = util.capture(("%s tools/run.lua link-modules %s 2>&1"):format(util.quote(util.interpreter()), util.quote(base --[[@as string]])))
  self:assert_true(ok, out)
  local share = base .. "/lua_modules/share/lua/" .. _VERSION:match("%d+%.%d+") .. "/hecate"
  self:assert_true(util.exists(share .. "/core/init.lua"), "core")
  self:assert_true(util.exists(share .. "/cli/main.lua"), "cli")
  self:assert_true(util.exists(share .. "/init.lua"), "the meta-module hecate")
  util.remove_tree(base --[[@as string]])
end

function T:test_a_missing_argument_is_reported()
  local _, ok = util.capture(("%s tools/run.lua link-modules 2>&1"):format(util.quote(util.interpreter())))
  self:assert_false(ok)
end

return T
