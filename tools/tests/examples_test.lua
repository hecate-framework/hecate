local test = require("harness.test")
local examples = require("lib.examples")
local runner = require("harness.examples")
local util = require("lib.util")
local T = test.Case("ExamplesTest")

local LONG = string.rep("x", 70)

-- Rule 1: width of the lines that hold a comment.

function T:test_a_short_comment_line_passes()
  self:assert_equal(0, #examples.check_source("local x = 1 -- short\n-- also short\n"))
end

function T:test_a_comment_line_over_the_width_is_reported_with_its_number()
  local problems = examples.check_source("local x = 1\nlocal y = 2 -- " .. LONG .. "\n")
  self:assert_equal(1, #problems)
  self:assert_equal(2, problems[1].line)
  self:assert_not_nil(problems[1].message:find("at most 80", 1, true))
end

function T:test_the_width_counts_indentation_and_code_before_the_comment()
  local line = string.rep(" ", 10) .. "call(" .. string.rep("a", 60) .. ") -- why"
  self:assert_equal(1, #examples.check_source(line .. "\n"))
end

function T:test_a_long_code_line_without_a_comment_passes()
  self:assert_equal(0, #examples.check_source("local s = 'a' .. '" .. LONG .. LONG .. "'\n"))
end

function T:test_dashes_inside_a_string_are_not_a_comment()
  self:assert_equal(0, #examples.check_source("print('--" .. LONG .. LONG .. "')\nprint(\"--" .. LONG .. "\")\n"))
end

function T:test_dashes_inside_a_long_string_are_not_a_comment()
  self:assert_equal(0, #examples.check_source("local s = [==[\n--" .. LONG .. LONG .. "\n]==]\nprint(s)\n"))
end

function T:test_every_line_of_a_long_comment_is_checked()
  local problems = examples.check_source("--[[ start\n" .. LONG .. LONG .. "\nend ]]\nlocal x = 1\n")
  self:assert_equal(1, #problems)
  self:assert_equal(2, problems[1].line)
end

function T:test_the_exemption_marker_on_the_line_above_exempts_one_line()
  local source = "-- " .. examples.EXEMPTION .. "\nlocal x = 1 -- " .. LONG .. "\nlocal y = 2 -- " .. LONG .. "\n"
  local problems = examples.check_source(source)
  self:assert_equal(1, #problems)
  self:assert_equal(3, problems[1].line)
end

function T:test_the_width_is_counted_in_characters_not_bytes()
  self:assert_equal(0, #examples.check_source("-- " .. string.rep("é", 77) .. "\n"))
  self:assert_equal(1, #examples.check_source("-- " .. string.rep("é", 78) .. "\n"))
end

function T:test_an_unfinished_string_does_not_hide_the_next_lines()
  self:assert_equal(1, #examples.check_source("print('open\n-- " .. LONG .. LONG .. "\n"))
end

function T:test_markdown_lua_blocks_are_checked_with_page_line_numbers()
  local page = "# Title\n\n```lua\nlocal x = 1 -- " .. LONG .. "\n```\n\n```sh\n# " .. LONG .. LONG .. "\n```\n"
  local problems = examples.check_markdown(page)
  self:assert_equal(1, #problems)
  self:assert_equal(4, problems[1].line)
end

function T:test_markdown_blocks_copied_from_an_example_file_are_left_to_that_file()
  local page = "<!-- example: packages/x/examples/a.lua -->\n```lua\nlocal x = 1 -- " .. LONG .. "\n```\n"
  self:assert_equal(0, #examples.check_markdown(page))
end

-- Rule 2: output written directly under the line that prints it.

local function outputs(list)
  local result = {}
  for index, pair in ipairs(list) do result[index] = { line = pair[1], text = pair[2] } end
  return result
end

function T:test_each_print_followed_by_its_block_passes()
  local source = "print('a')\n-- Prints: a\nprint('b')\n-- Prints: b\n"
  self:assert_nil(runner.compare(source, outputs({ { 1, "a" }, { 3, "b" } })))
end

function T:test_a_block_continues_on_the_comment_lines_that_follow_it()
  local source = "print('a\\nb')\n-- Prints: a\n-- b\nlocal x = 1\n"
  self:assert_nil(runner.compare(source, outputs({ { 1, "a" }, { 1, "b" } })))
end

function T:test_output_gathered_at_the_end_is_refused()
  local source = "print('a')\nprint('b')\n-- Prints: a\n-- b\n"
  local problem = runner.compare(source, outputs({ { 1, "a" }, { 2, "b" } }))
  self:assert_not_nil(problem and problem:find("same `-- Prints:` block", 1, true), problem)
end

function T:test_a_block_separated_from_its_line_is_refused()
  local source = "print('a')\nlocal x = 1\n\n-- Prints: a\n"
  local problem = runner.compare(source, outputs({ { 1, "a" } }))
  self:assert_not_nil(problem and problem:find("not directly under", 1, true), problem)
end

function T:test_the_rest_of_the_statement_may_stand_between_the_line_and_its_block()
  local source = "for i = 1, 2 do\n  print(i)\nend\n-- Prints: 1\n-- 2\n"
  self:assert_nil(runner.compare(source, outputs({ { 2, "1" }, { 2, "2" } })))
end

function T:test_output_without_a_block_is_refused()
  local problem = runner.compare("local x = 1\nprint('a')\n", outputs({ { 2, "a" } }))
  self:assert_not_nil(problem and problem:find("no `-- Prints:` block follows", 1, true), problem)
end

function T:test_a_block_nothing_prints_is_refused()
  local problem = runner.compare("local x = 1\n-- Prints: a\n", {})
  self:assert_not_nil(problem and problem:find("nothing printed it", 1, true), problem)
end

function T:test_a_different_output_is_refused()
  local problem = runner.compare("print('b')\n-- Prints: a\n", outputs({ { 1, "b" } }))
  self:assert_not_nil(problem and problem:find("expects", 1, true), problem)
end

function T:test_run_attributes_each_print_to_its_line_in_the_example()
  local path = os.tmpname()
  local file = assert(io.open(path, "wb"))
  file:write("local function each(f) f() end\neach(function()\n  print('inner')\n  -- Prints: inner\nend)\n"
    .. "print(1, nil)\n-- Prints: 1\tnil\n")
  file:close()
  local ok, problem = pcall(runner.run, path)
  os.remove(path)
  self:assert_true(ok, tostring(problem))
  self:assert_nil(problem, problem)
end

function T:test_run_reports_an_error_of_the_example()
  local path = os.tmpname()
  local file = assert(io.open(path, "wb"))
  file:write("error('broken')\n")
  file:close()
  local ok, problem = pcall(runner.run, path)
  os.remove(path)
  self:assert_true(ok, tostring(problem))
  self:assert_not_nil(problem and problem:find("broken", 1, true), problem)
end

-- Review findings of 2026-11-12 (test-engineer).

function T:test_a_z_escape_does_not_end_the_string()
  self:assert_equal(1, #examples.check_source('local s = "a\\z\n  b" -- ' .. LONG .. LONG .. "\n"))
end

function T:test_an_escaped_crlf_line_break_stays_inside_the_string()
  self:assert_equal(0, #examples.check_source('local s = "a\\\r\n--' .. LONG .. LONG .. '"\r\nprint(s)\r\n'))
end

function T:test_a_crlf_source_is_measured_without_carriage_returns()
  local line = "-- " .. string.rep("x", 77)
  self:assert_equal(0, #examples.check_source(line .. "\r\n" .. line .. "\r\n"))
end

function T:test_an_unclosed_long_comment_runs_to_the_end_of_the_file()
  self:assert_equal(1, #examples.check_source("--[[ open\n" .. LONG .. LONG .. "\n"))
end

function T:test_a_mismatched_long_bracket_level_does_not_close_the_string()
  self:assert_equal(0, #examples.check_source("local s = [==[ ]] --" .. LONG .. LONG .. "\n]==]\n"))
end

function T:test_a_comment_at_the_end_of_the_file_without_a_newline_is_checked()
  self:assert_equal(1, #examples.check_source("local x = 1\n-- " .. LONG .. LONG))
end

function T:test_tilde_capitalised_and_annotated_fences_are_checked()
  local body = "local x = 1 -- " .. LONG .. "\n"
  self:assert_equal(1, #examples.check_markdown("~~~lua\n" .. body .. "~~~\n"))
  self:assert_equal(1, #examples.check_markdown("```Lua\n" .. body .. "```\n"))
  self:assert_equal(1, #examples.check_markdown("```lua title=x\n" .. body .. "```\n"))
  self:assert_equal(0, #examples.check_markdown("```luax\n" .. body .. "```\n"))
end

function T:test_the_exemption_must_be_a_comment_line_of_its_own()
  local source = "f() -- " .. examples.EXEMPTION .. "\nlocal x = 1 -- " .. LONG .. "\n"
  self:assert_equal(1, #examples.check_source(source))
end

function T:test_ordinary_code_between_a_print_and_its_block_is_refused()
  local problem = runner.compare("print('a')\nlocal x = 1\nlocal y = 2\n-- Prints: a\n", outputs({ { 1, "a" } }))
  self:assert_not_nil(problem and problem:find("not directly under", 1, true), problem)
end

function T:test_a_block_under_a_line_that_prints_nothing_is_refused()
  local problem = runner.compare("print('a')\nquiet()\n-- Prints: a\n", outputs({ { 1, "a" } }))
  self:assert_not_nil(problem and problem:find("not directly under", 1, true), problem)
end

function T:test_the_arguments_of_a_multi_line_print_may_stand_before_its_block()
  local source = "print(\n  'a',\n  'b'\n)\n-- Prints: a\tb\n"
  self:assert_nil(runner.compare(source, outputs({ { 1, "a\tb" } })))
end

function T:test_a_prints_line_inside_a_long_comment_or_string_is_not_a_block()
  local source = "print('a')\n-- Prints: a\nlocal s = [[\n-- Prints: b\n]]\n--[[\n-- Prints: c\n]]\n"
  self:assert_nil(runner.compare(source, outputs({ { 1, "a" } })))
end

function T:test_output_not_attributable_to_a_line_is_refused()
  local problem = runner.compare("print('a')\n-- Prints: a\n", outputs({ { 0, "a" } }))
  self:assert_not_nil(problem and problem:find("not attributable", 1, true), problem)
end

local function with_file(text, fn)
  local path = os.tmpname()
  local file = assert(io.open(path, "wb"))
  file:write(text)
  file:close()
  local ok, result = pcall(fn, path)
  os.remove(path)
  if not ok then error(result, 0) end
  return result
end

function T:test_print_through_the_global_table_is_captured()
  local problem = with_file("_G.print('a')\n-- Prints: a\n", runner.run)
  self:assert_nil(problem, problem)
end

function T:test_writing_to_the_standard_output_is_refused()
  local problem = with_file("io.write('a\\n')\n", runner.run)
  self:assert_not_nil(problem and problem:find("print", 1, true), problem)
end

local function remove_tree(path)
  if util.is_windows() then os.execute(('rmdir /s /q "%s" >nul 2>&1'):format(path:gsub("/", "\\")))
  else os.execute("rm -rf " .. util.quote(path)) end
end

function T:test_the_task_reports_examples_and_pages_with_their_lines()
  -- a fixture tree inside the git-ignored `.hecate/` of the repository: on the Windows runners, the shell listing
  -- of `util.list_dir` found nothing under the temporary directory (`C:/Users/RUNNER~1/...`)
  local here = debug.getinfo(1, "S").source:sub(2):gsub("\\", "/")
  local repository = here:match("^(.*)/tools/tests/") or "."
  local root = ("%s/.hecate/check-examples-%d-%d"):format(repository, os.time(), math.random(1, 1000000))
  local function write(path, text)
    util.mkdir((root .. "/" .. path):match("^(.*)/"))
    local f = assert(io.open(root .. "/" .. path, "wb"))
    f:write(text)
    f:close()
  end
  write("packages/x/examples/a.lua", "local x = 1\nlocal y = 2 -- " .. LONG .. "\n")
  write("examples/app/main.lua", "-- short\n")
  write("website/en/how-to/p.md", "# P\n\n```lua\n-- " .. LONG .. LONG .. "\n```\n")
  write("website/fr/how-to/p.md", "# P\n\n```lua\n-- " .. LONG .. LONG .. "\n```\n")
  write("website/en/reference/r.md", "```lua\n-- " .. LONG .. LONG .. "\n```\n")
  local ok, report = pcall(require("tasks.check_examples").run, { root = root, args = {} })
  remove_tree(root)
  self:assert_true(ok, tostring(report))
  local seen = ("root %s, %d files, problems:\n%s"):format(root, report.count, table.concat(report.problems, "\n"))
  self:assert_false(report.ok, seen)
  table.sort(report.problems)
  self:assert_equal(3, #report.problems, seen)
  self:assert_not_nil(report.problems[1]:find("^packages/x/examples/a%.lua:2: "), report.problems[1])
  self:assert_not_nil(report.problems[2]:find("^website/en/how%-to/p%.md:4: "), report.problems[2])
  self:assert_not_nil(report.problems[3]:find("^website/fr/how%-to/p%.md:4: "), report.problems[3])
end

return T
