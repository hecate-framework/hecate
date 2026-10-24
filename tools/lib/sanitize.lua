-- Helpers of the `sanitize` task: compiler flags and runtime environment of ASan/UBSan builds.
local M = {}

--- Compiler flags of a sanitizer build (the C modules, coding-standards.md "C code").
---@return string
function M.cflags()
  return "-fsanitize=address,undefined -fno-sanitize-recover=undefined -fno-omit-frame-pointer -g -O1"
end

--- Returns the runtime library to preload for an uninstrumented interpreter, from `cc -print-file-name`
--- output; nil when the compiler did not find it (it echoes the bare name back).
---@param printed string
---@return string?
function M.runtime(printed)
  printed = printed:gsub("%s+$", "")
  if printed == "" or not printed:find("/", 1, true) then return nil end
  return printed
end

--- Environment prefix of a command run under the sanitizers: the interpreter is not instrumented, so the
--- runtime is preloaded, and leaks of the interpreter itself are not reported.
---@param runtime string
---@return string
function M.environment(runtime)
  return ("LD_PRELOAD=%s ASAN_OPTIONS=detect_leaks=0:abort_on_error=0 UBSAN_OPTIONS=print_stacktrace=1:halt_on_error=1"):format(runtime)
end

return M
