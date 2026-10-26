-- fuzz <target> [--seconds n]: runs one libFuzzer target for a bounded time. `fuzz --list` prints the targets.
-- Rust targets (cargo-fuzz, nightly toolchain) live in packages/<name>/native/fuzz/fuzz_targets/<target>.rs;
-- C targets (clang with libFuzzer, ASan and UBSan; needs the Lua headers and liblua.a: LUA_INC and LUA_LIB, or next
-- to the interpreter or in the bootstrapped toolchain) in packages/<name>/csrc/fuzz/<target>.c, with their seed inputs
-- in the `seeds` directory beside them.
local util = require("lib.util")
local fuzz = require("lib.fuzz")

local function targets(root)
  local found = {}
  for _, path in ipairs(util.walk(root .. "/packages", ".rs")) do
    local package, name = path:match("/packages/([^/]+)/native/fuzz/fuzz_targets/([^/]+)%.rs$")
    if package then found[#found + 1] = { package = package, name = name, kind = "rust" } end
  end
  for _, path in ipairs(util.walk(root .. "/packages", ".c")) do
    local package, name = path:match("/packages/([^/]+)/csrc/fuzz/([^/]+)%.c$")
    if package then found[#found + 1] = { package = package, name = name, kind = "c" } end
  end
  table.sort(found, function(a, b) return a.package .. a.name < b.package .. b.name end)
  return found
end

-- The directory holding `file` among the candidates, nil when none does.
local function locate(file, candidates)
  for _, dir in ipairs(candidates) do
    if dir ~= "" and util.exists(dir .. "/" .. file) then return dir end
  end
  return nil
end

local function run_c(ctx, target, seconds)
  local toolchain = ctx.root .. "/.hecate/toolchain"
  local exe = util.interpreter():gsub("\\", "/")
  if not exe:find("/", 1, true) then exe = util.capture("command -v " .. util.quote(exe)):gsub("%s+$", "") end
  local prefix = exe:match("^(.*)/bin/[^/]*$")
  local include = locate("lua.h", { os.getenv("LUA_INC") or "", toolchain .. "/include", prefix and prefix .. "/include" or "" })
  local libdir = locate("liblua.a", { os.getenv("LUA_LIB") or "", toolchain .. "/lib", prefix and prefix .. "/lib" or "" })
  if not include or not libdir then
    return { ok = false, problems = { "lua.h or liblua.a not found: set LUA_INC and LUA_LIB to the Lua include and library directories" } }
  end
  local package_dir = ctx.root .. "/packages/" .. target.package .. "/csrc/fuzz"
  local work = ("%s/.hecate/fuzz/%s"):format(ctx.root, target.name)
  local corpus, artifacts = work .. "/corpus", package_dir .. "/artifacts"
  util.mkdir(corpus)
  util.mkdir(artifacts)
  local command = fuzz.c_command({
    cc = os.getenv("CC") or "clang", include = include, lib = libdir .. "/liblua.a", source = package_dir .. "/" .. target.name .. ".c",
    binary = work .. "/fuzzer", corpus = corpus, seeds = package_dir .. "/seeds", artifacts = artifacts,
  }, seconds)
  local out, ok = util.capture(command .. " 2>&1")
  if not ok then return { ok = false, problems = { "fuzzing " .. target.name .. " failed to build or found a crash (last 80 lines):\n" .. fuzz.tail(out, 80) } } end
  return { ok = true, problems = {} }
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
    if target.kind == "c" then return run_c(ctx, target, options.seconds) end
    local out, ok = util.capture(fuzz.command(ctx.root .. "/packages/" .. target.package .. "/native", target.name,
      options.seconds) .. " 2>&1")
    if not ok then return { ok = false, problems = { "fuzzing " .. target.name .. " found a failure or did not run (last 80 lines):\n" .. fuzz.tail(out, 80) } } end
    return { ok = true, problems = {} }
  end,
}
