-- fuzz <target> [--seconds n]: runs one libFuzzer target (cargo-fuzz, nightly toolchain) of a package's native
-- crate for a bounded time. `fuzz --list` prints the targets. Targets live in packages/<name>/native/fuzz/fuzz_targets.
local util = require("lib.util")
local fuzz = require("lib.fuzz")

local function targets(root)
  local found = {}
  for _, path in ipairs(util.walk(root .. "/packages", ".rs")) do
    local package, name = path:match("/packages/([^/]+)/native/fuzz/fuzz_targets/([^/]+)%.rs$")
    if package then found[#found + 1] = { package = package, name = name } end
  end
  table.sort(found, function(a, b) return a.package .. a.name < b.package .. b.name end)
  return found
end

return {
  description = "run a libFuzzer target for a bounded time (--list shows the targets)",
  run = function(ctx)
    local all = targets(ctx.root)
    if ctx.args[1] == "--list" then
      for _, t in ipairs(all) do print(t.package .. " " .. t.name) end
      return { ok = true, problems = {} }
    end
    local options = fuzz.parse(ctx.args)
    if not options then return { ok = false, problems = { "usage: fuzz <target> [--seconds n] | fuzz --list" } } end
    local target = fuzz.find(all, options.target)
    if not target then return { ok = false, problems = { "unknown fuzz target: " .. options.target } } end
    local out, ok = util.capture(fuzz.command(ctx.root .. "/packages/" .. target.package .. "/native", target.name,
      options.seconds) .. " 2>&1")
    if not ok then return { ok = false, problems = { "fuzzing " .. target.name .. " found a failure or did not run (last 80 lines):\n" .. fuzz.tail(out, 80) } } end
    return { ok = true, problems = {} }
  end,
}
