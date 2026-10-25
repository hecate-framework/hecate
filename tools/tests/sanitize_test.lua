local test = require("harness.test")
local sanitize = require("lib.sanitize")
local T = test.Case("SanitizeTest")

function T:test_cflags_enable_both_sanitizers_and_stop_on_undefined_behaviour()
  local flags = sanitize.cflags()
  self:assert_true(flags:find("address,undefined", 1, true) ~= nil)
  self:assert_true(flags:find("-fsanitize-undefined-trap-on-error", 1, true) ~= nil)
end

function T:test_runtime_accepts_a_path_and_rejects_a_bare_name()
  self:assert_equal("/usr/lib/gcc/x86_64-linux-gnu/13/libasan.so", sanitize.runtime("/usr/lib/gcc/x86_64-linux-gnu/13/libasan.so\n"))
  self:assert_nil(sanitize.runtime("libasan.so\n"))
  self:assert_nil(sanitize.runtime(""))
end

function T:test_the_runtime_name_depends_on_the_platform()
  self:assert_equal("libasan.so", sanitize.runtime_name(false))
  self:assert_equal("libclang_rt.asan_osx_dynamic.dylib", sanitize.runtime_name(true))
end

function T:test_environment_inserts_the_runtime_with_dyld_on_macos()
  local env = sanitize.environment("/x/libclang_rt.asan_osx_dynamic.dylib", true)
  self:assert_true(env:find("DYLD_INSERT_LIBRARIES=/x/libclang_rt.asan_osx_dynamic.dylib", 1, true) == 1)
  self:assert_nil(env:find("LD_PRELOAD", 1, true))
end

function T:test_environment_preloads_the_runtime()
  self:assert_true(sanitize.environment("/x/libasan.so"):find("LD_PRELOAD=/x/libasan.so", 1, true) == 1)
end

return T
