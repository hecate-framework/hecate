-- check-docs-examples: every code block that website pages take from an example file is exact,
-- and the file exists (the examples themselves run in the tests of their package).
local util = require("lib.util")
local docs_examples = require("lib.docs_examples")

local SKIP = { node_modules = true, dist = true }

local function read(path)
  local f = io.open(path, "rb")
  if not f then return nil end
  local s = f:read("a")
  f:close()
  return s
end

--- Markdown pages under `dir`, except the generated reference and the build output.
local function pages(dir, rel, out)
  for _, name in ipairs(util.list_dir(dir)) do
    local path, r = dir .. "/" .. name, rel .. "/" .. name
    if not SKIP[name] then
      if util.is_dir(path) then
        if name ~= "reference" then pages(path, r, out) end
      elseif name:sub(-3) == ".md" then
        out[#out + 1] = r
      end
    end
  end
  return out
end

return {
  description = "code blocks of website pages match the example files they cite",
  run = function(ctx)
    local problems, count = {}, 0
    for _, rel in ipairs(pages(ctx.root .. "/website", "website", {})) do
      local text = read(ctx.root .. "/" .. rel) or ""
      if text:find("<!--%s*example:") then count = count + 1 end
      for _, problem in ipairs(docs_examples.check(text, function(path) return read(ctx.root .. "/" .. path) end)) do
        problems[#problems + 1] = ("%s:%d: %s"):format(rel, problem.line, problem.message)
      end
    end
    return { ok = #problems == 0, problems = problems, count = count }
  end,
}
