local hecate_test = require("hecate.test")
local terminal = require("hecate.test.reporters.terminal")
local ansi = require("hecate.test.reporters.ansi")
local T = hecate_test.Case("TerminalTest")

local function env(values) return function(name) return values[name] end end

function T:test_colour_follows_no_color_force_color_and_the_terminal()
  local function colour(values, tty) return terminal.resolve({ getenv = env(values), is_tty = tty }).color end
  self:assert_true(colour({}, true))
  self:assert_false(colour({}, false))
  self:assert_false(colour({ NO_COLOR = "1" }, true))
  self:assert_true(colour({ FORCE_COLOR = "1" }, false))
  self:assert_false(colour({ FORCE_COLOR = "0" }, false))
  self:assert_false(colour({ NO_COLOR = "1", FORCE_COLOR = "1" }, true), "NO_COLOR wins over FORCE_COLOR")
  self:assert_true(colour({ NO_COLOR = "" }, true), "an empty NO_COLOR is ignored")
end

function T:test_an_explicit_option_beats_the_environment()
  local resolved = terminal.resolve({ color = false, live = true, getenv = env({ FORCE_COLOR = "1" }), is_tty = false })
  self:assert_false(resolved.color)
  self:assert_true(resolved.live)
  resolved = terminal.resolve({ color = true, live = false, getenv = env({ NO_COLOR = "1" }), is_tty = true })
  self:assert_true(resolved.color)
  self:assert_false(resolved.live)
end

function T:test_live_mode_follows_the_terminal()
  self:assert_true(terminal.resolve({ getenv = env({}), is_tty = true }).live)
  self:assert_false(terminal.resolve({ getenv = env({}), is_tty = function() return false end }).live)
end

function T:test_the_terminal_is_not_probed_when_the_options_decide_everything()
  local probed = false
  terminal.resolve({ color = true, live = false, width = 50, getenv = env({}), is_tty = function() probed = true; return true end })
  self:assert_false(probed)
end

function T:test_width_comes_from_the_option_then_columns_then_80()
  local function width(options, values) options.getenv = env(values or {}); options.is_tty = false; return terminal.resolve(options).width end
  self:assert_equal(80, width({}))
  self:assert_equal(132, width({}, { COLUMNS = "132" }))
  self:assert_equal(80, width({}, { COLUMNS = "wide" }))
  self:assert_equal(80, width({}, { COLUMNS = "0" }))
  self:assert_equal(50, width({ width = 50 }, { COLUMNS = "132" }))
end

function T:test_hecate_test_live_decides_after_the_option_and_before_the_terminal_guess()
  local function live(values, options)
    options = options or {}
    options.getenv = env(values); if options.is_tty == nil then options.is_tty = true end
    return terminal.resolve(options).live
  end
  self:assert_false(live({ HECATE_TEST_LIVE = "0" }))
  self:assert_true(live({ HECATE_TEST_LIVE = "1" }, { is_tty = false }))
  self:assert_true(live({ HECATE_TEST_LIVE = "0" }, { live = true }), "the option wins")
  self:assert_true(live({ HECATE_TEST_LIVE = "" }), "an empty value is ignored")
  self:assert_true(live({ HECATE_TEST_LIVE = "maybe" }), "an unknown value is ignored")
end

function T:test_the_probe_is_false_for_a_child_whose_output_is_a_pipe()
  if package.config:sub(1, 1) ~= "/" then return end
  local pipe = assert(io.popen("test -t 1 && echo tty || echo pipe"))
  local out = pipe:read("a") or ""
  pipe:close()
  self:assert_equal("pipe\n", out)
end

-- Runs `lua` on a one-line chunk that prints whether the terminal probe says "tty", through `prefix`.
local function probe(wrap)
  local chunk = 'package.path=[==[' .. package.path .. ']==];package.cpath=[==[' .. package.cpath .. ']==];'
    .. 'local t=require("hecate.test.reporters.terminal");'
    .. 'io.write(tostring(t.stdout_is_tty(function(n) if n=="TERM" then return "xterm" end end)))'
  local command = "lua -e '" .. chunk .. "'"
  local pipe = assert(io.popen((wrap and wrap(command) or command) .. " 2>&1"))
  local out = pipe:read("a") or ""
  pipe:close()
  return out
end

function T:test_the_probe_says_tty_under_a_pty_and_no_on_a_pipe()
  if package.config:sub(1, 1) ~= "/" then return end
  self:assert_match("false$", probe())
  local has_script = os.execute("command -v script >/dev/null 2>&1")
  if has_script ~= true then return end -- util-linux or BSD `script` missing: skipped
  -- util-linux: script -qec CMD /dev/null; the BSD form differs and is skipped when it fails
  local out = probe(function(command) return 'script -qec "' .. command .. '" /dev/null' end)
  if out:find("true", 1, true) == nil and out:find("false", 1, true) == nil then return end
  self:assert_match("true", out)
end

function T:test_a_pipe_is_not_a_terminal_when_the_standard_output_is_redirected()
  self:assert_false(terminal.stdout_is_tty(env({ TERM = "dumb" })))
  self:assert_false(terminal.stdout_is_tty(env({})))
end

function T:test_ansi_paints_only_when_enabled()
  self:assert_equal("x", ansi.paint("x", "green", false))
  self:assert_equal("\27[32mx\27[0m", ansi.paint("x", "green", true))
  self:assert_equal("\27[31mx\27[0m", ansi.paint("x", "red", true))
  self:assert_equal("\27[38;5;208mx\27[0m", ansi.paint("x", "orange", true))
  self:assert_equal("\r\27[2K", ansi.REDRAW)
end

return require("hecate.core").finalise(T)
