-- sanitize [package...]: builds the C modules of the named packages (default: json, the only package with C
-- code) with ASan and UBSan into the rocks tree and runs their tests against it. Linux only, with GCC or Clang:
-- the interpreter is not instrumented, so the ASan runtime is preloaded with LD_PRELOAD (macOS would need
-- DYLD_INSERT_LIBRARIES and its own runtime lookup, not done). The Rust code is not covered (it is memory-safe
-- outside `unsafe`; the cargo-fuzz targets exercise its boundary).
local util = require("lib.util")
local sanitize = require("lib.sanitize")

return {
  description = "build native modules with ASan/UBSan and run their tests",
  run = function(ctx)
    if util.is_windows() or util.capture("uname -s"):find("Darwin", 1, true) then
      return { ok = false, problems = { "sanitize runs on Linux only (it preloads the ASan runtime with LD_PRELOAD)" } }
    end
    local cc = os.getenv("CC") or "cc"
    local runtime = sanitize.runtime(util.capture(cc .. " -print-file-name=libasan.so"))
    if not runtime then return { ok = false, problems = { "the AddressSanitizer runtime was not found for " .. cc } } end
    local packages = #ctx.args > 0 and ctx.args or { "json" }
    local env = sanitize.environment(runtime)
    local problems = {}
    for _, name in ipairs(packages) do
      local built, ok = util.capture(("HECATE_SANITIZE=1 %s %s build-native %s 2>&1"):format(util.quote(util.interpreter()),
        util.quote(ctx.root .. "/tools/run.lua"), util.quote(name)))
      if not ok then
        problems[#problems + 1] = "sanitized build of " .. name .. " failed:\n" .. built
      else
        local out, passed = util.capture(("%s %s %s test %s 2>&1"):format(env, util.quote(util.interpreter()),
          util.quote(ctx.root .. "/tools/run.lua"), util.quote(name)))
        if not passed then problems[#problems + 1] = "tests of " .. name .. " under the sanitizers failed:\n" .. out end
      end
    end
    -- The sanitized modules replaced the normal ones in .hecate/rocks: restore them.
    for _, name in ipairs(packages) do
      util.capture(("%s %s build-native %s 2>&1"):format(util.quote(util.interpreter()),
        util.quote(ctx.root .. "/tools/run.lua"), util.quote(name)))
    end
    return { ok = #problems == 0, problems = problems }
  end,
}
