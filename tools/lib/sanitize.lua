-- Helpers of the `sanitize` task: compiler flags and runtime environment of ASan/UBSan builds.
local M = {}

--- Compiler flags of a sanitizer build (the C modules, coding-standards.md "C code"). Undefined behaviour
--- traps instead of calling the UBSan runtime: only the ASan runtime is preloaded into the (uninstrumented)
--- interpreter, and Clang's ASan runtime does not export the UBSan handlers.
---@return string
function M.cflags()
  return "-fsanitize=address,undefined -fsanitize-undefined-trap-on-error -fno-omit-frame-pointer -g -O1"
end

--- File name of the AddressSanitizer runtime to preload: a shared object on Linux, a dynamic library of the
--- Clang runtime on macOS (Apple's compiler driver is Clang, whatever `CC` says).
---@param darwin boolean
---@return string
function M.runtime_name(darwin)
  return darwin and "libclang_rt.asan_osx_dynamic.dylib" or "libasan.so"
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
--- runtime is preloaded (`LD_PRELOAD`, `DYLD_INSERT_LIBRARIES` on macOS), and leaks of the interpreter itself
--- are not reported. The prefix is set on the command itself, not exported by a shell: macOS drops
--- `DYLD_*` variables when a protected system binary such as `/bin/sh` starts a program.
---@param runtime string
---@param darwin? boolean
---@return string
function M.environment(runtime, darwin)
  local preload = darwin and "DYLD_INSERT_LIBRARIES" or "LD_PRELOAD"
  return ("%s=%s ASAN_OPTIONS=detect_leaks=0:abort_on_error=0 UBSAN_OPTIONS=print_stacktrace=1:halt_on_error=1"):format(preload, runtime)
end

return M
