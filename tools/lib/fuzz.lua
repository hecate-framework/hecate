-- Helpers of the `fuzz` task: argument parsing, target lookup and the cargo-fuzz command line.
local util = require("lib.util")

local M = {}

--- Parses `<target> [--seconds n]`; nil when the arguments are invalid.
---@param args string[]
---@return {target: string, seconds: integer}?
function M.parse(args)
  local options = { seconds = 60 }
  local i = 1
  while i <= #args do
    local a = args[i]
    if a == "--seconds" then
      local n = math.tointeger(tonumber(args[i + 1]))
      if not n or n < 1 then return nil end
      options.seconds = n
      i = i + 1
    elseif not options.target and a:sub(1, 2) ~= "--" then
      options.target = a
    else
      return nil
    end
    i = i + 1
  end
  if not options.target then return nil end
  return options
end

--- Finds a target by name.
---@param targets {package: string, name: string}[]
---@param name string
---@return {package: string, name: string}?
function M.find(targets, name)
  for _, t in ipairs(targets) do
    if t.name == name then return t end
  end
  return nil
end

--- Command line that fuzzes one target for a bounded time (coding-standards.md; packages/net/native/fuzz/README.md).
---@param crate string directory of the Rust crate
---@param name string
---@param seconds integer
---@return string
function M.command(crate, name, seconds)
  return ("cd %s && cargo +nightly fuzz run %s -- -max_total_time=%d"):format(util.quote(crate), name, seconds)
end

--- Command line that builds and runs one C libFuzzer target (clang with the fuzzer, AddressSanitizer and
--- UndefinedBehaviorSanitizer runtimes), linked against the static Lua library: the harness includes the module's
--- own source. `seeds` is read-only input; findings of the run grow `corpus`; a crash is written to `artifacts`.
---@param spec {cc: string, include: string, lib: string, source: string, binary: string, corpus: string, seeds: string, artifacts: string}
---@param seconds integer
---@return string
function M.c_command(spec, seconds)
  local q = util.quote
  return ("%s -std=c11 -O1 -g -fno-omit-frame-pointer -fsanitize=fuzzer,address,undefined -I%s -o %s %s %s -lm -ldl && "
    .. "%s %s %s -artifact_prefix=%s/ -max_total_time=%d"):format(spec.cc, q(spec.include), q(spec.binary), q(spec.source),
    q(spec.lib), q(spec.binary), q(spec.corpus), q(spec.seeds), q(spec.artifacts), seconds)
end

--- The last `count` lines of a report: a fuzzer prints a line per new input, and the verdict (the crash, its
--- stack trace and the path of the input that reproduces it) is at the end.
---@param text string
---@param count integer
---@return string
function M.tail(text, count)
  local lines = {}
  for line in text:gmatch("[^\r\n]+") do lines[#lines + 1] = line end
  if #lines <= count then return table.concat(lines, "\n") end
  return ("... (%d earlier lines omitted)\n"):format(#lines - count) .. table.concat(lines, "\n", #lines - count + 1)
end

return M
