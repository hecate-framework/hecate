local core = require("hecate.core")
local hecate_test = require("hecate.test")
local T = hecate_test.Case("SelectionTest")

local function names(options, cases)
  local list = {}
  for _, t in ipairs(hecate_test.Runner(options):plan(cases)) do list[#list + 1] = t.full_name end
  return table.concat(list, ",")
end

function T:test_the_cases_option_keeps_only_the_named_cases()
  local A, B = hecate_test.Case("A"), hecate_test.Case("B")
  function A:test_x() end
  function B:test_y() end
  self:assert_equal("A.test_x,B.test_y", names({}, { A, B }))
  self:assert_equal("B.test_y", names({ cases = { "B" } }, { A, B }))
  self:assert_equal("A.test_x,B.test_y", names({ cases = { "A", "B" } }, { A, B }))
  self:assert_equal("", names({ cases = { "Missing" } }, { A, B }))
  ---@type any
  local text = "A"
  self:assert_error(function() hecate_test.Runner({ cases = text }) end, { class = core.ArgumentError })
end

function T:test_arguments_become_runner_options_and_paths()
  local selection = hecate_test.parse_arguments({
    "--filter=^A%.", "--case=A", "--case", "B", "--tag=slow", "--exclude-tag=net", "tests/unit", "x_test.lua" })
  self:assert_equal("^A%.", selection.options.filter)
  self:assert_equal("A,B", table.concat(selection.options.cases, ","))
  self:assert_equal("slow", table.concat(selection.options.tags, ","))
  self:assert_equal("net", table.concat(selection.options.exclude_tags, ","))
  self:assert_equal("tests/unit,x_test.lua", table.concat(selection.paths, ","))
end

function T:test_no_argument_selects_everything_and_double_dash_ends_options()
  local none = hecate_test.parse_arguments({})
  self:assert_equal(0, #none.paths)
  self:assert_equal(nil, none.options.filter)
  local ended = hecate_test.parse_arguments({ "--", "--odd_test.lua" })
  self:assert_equal("--odd_test.lua", ended.paths[1])
end

function T:test_a_bad_argument_is_an_argument_error_naming_it()
  local function bad(args) self:assert_error(function() hecate_test.parse_arguments(args) end, { class = core.ArgumentError }) end
  bad({ "--unknown" })
  bad({ "--filter" })
  bad({ "--filter=a", "--filter=b" })
  bad({ "--tag=" })
end

return core.finalise(T)
