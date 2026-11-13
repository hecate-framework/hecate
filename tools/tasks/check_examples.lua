-- check-examples: no line holding a comment is longer than 80 characters in the code examples
-- (`packages/*/examples/**`, `examples/**`, the Lua blocks of `website/<locale>/**`), unless the line
-- above carries the exemption marker. The placement of printed output is checked when the
-- examples run (`tools/harness/examples.lua`).
local util = require("lib.util")
local examples = require("lib.examples")

local SKIP = { node_modules = true, dist = true, reference = true }

local function read(path)
  local f = io.open(path, "rb")
  if not f then return nil end
  local s = f:read("a")
  f:close()
  return s
end

--- Files under `dir` whose name ends with `suffix`, as paths relative to the root.
local function walk(root, rel, suffix, out)
  local dir = root .. "/" .. rel
  if not util.is_dir(dir) then return out end
  for _, name in ipairs(util.list_dir(dir)) do
    local child = rel .. "/" .. name
    if not SKIP[name] then
      if util.is_dir(root .. "/" .. child) then
        walk(root, child, suffix, out)
      elseif name:sub(-#suffix) == suffix then
        out[#out + 1] = child
      end
    end
  end
  return out
end

return {
  description = "lines holding a comment in code examples are at most 80 characters (exemption marker on the line above)",
  run = function(ctx)
    local root, problems, count = ctx.root, {}, 0
    local sources = walk(root, "examples", ".lua", {})
    for _, package in ipairs(util.list_dir(root .. "/packages")) do
      walk(root, "packages/" .. package .. "/examples", ".lua", sources)
    end
    table.sort(sources)
    for _, rel in ipairs(sources) do
      count = count + 1
      for _, problem in ipairs(examples.check_source(read(root .. "/" .. rel) or "")) do
        problems[#problems + 1] = ("%s:%d: %s"):format(rel, problem.line, problem.message)
      end
    end
    local pages = {}
    if util.is_dir(root .. "/website") then
      for _, locale in ipairs(util.list_dir(root .. "/website")) do
        if util.is_dir(root .. "/website/" .. locale) then walk(root, "website/" .. locale, ".md", pages) end
      end
    end
    table.sort(pages)
    for _, rel in ipairs(pages) do
      count = count + 1
      for _, problem in ipairs(examples.check_markdown(read(root .. "/" .. rel) or "")) do
        problems[#problems + 1] = ("%s:%d: %s"):format(rel, problem.line, problem.message)
      end
    end
    return { ok = #problems == 0, problems = problems, count = count }
  end,
}
