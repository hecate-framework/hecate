local test = require("harness.test")
local completion = require("hecate.cli.completion")
local T = test.Case("CliCompletionTest")

local commands = {
  { name = "version", summary = "x", run = function() end },
  { name = "serve", summary = "x", options = { { name = "watch", summary = "x" }, { name = "workers", takes_value = true, summary = "x" } }, run = function() end },
  { name = "toolchain install", summary = "x", run = function() end },
  { name = "toolchain list", summary = "x", run = function() end },
  { name = "__complete", summary = "x", hidden = true, run = function() end },
}

local function complete(...) return table.concat(completion.complete({ ... }, commands), " ") end

function T:test_first_word_completes_command_names_without_hidden_ones()
  self:assert_equal("serve toolchain version", complete(""))
  self:assert_equal("serve", complete("s"))
  self:assert_equal("", complete("__"))
  self:assert_equal("--help --json --version", complete("-"))
end

function T:test_second_word_of_a_two_word_command()
  self:assert_equal("install list", complete("toolchain", ""))
  self:assert_equal("install", complete("toolchain", "i"))
end

function T:test_options_of_the_selected_command()
  self:assert_equal("--watch --workers", complete("serve", "--w"))
  self:assert_equal("--help --json --watch --workers", complete("serve", "-"))
  self:assert_equal("", complete("serve", ""))
  self:assert_equal("--watch", complete("--json", "serve", "--wa"))
end

function T:test_unknown_command_has_no_candidates()
  self:assert_equal("", complete("frobnicate", ""))
end

function T:test_every_shell_has_a_script_that_calls_the_hidden_command()
  for _, shell in ipairs(completion.shells) do
    local script = completion.script(shell)
    self:assert_true(script:find("hecate __complete --", 1, true) ~= nil, shell)
  end
  local err = self:assert_error(function() completion.script("tcsh") end)
  self:assert_true(tostring(err):find("bash, zsh, fish, powershell", 1, true) ~= nil)
end

return T
