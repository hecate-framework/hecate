-- gen-config-reference: the "Configuration keys" reference page, from the framework keys of
-- packages/config/src/hecate/config/declaration.lua (loaded as a chunk with stand-ins for its dependencies, no
-- package is required) and the key tables of docs/architecture/configuration.md (tools/lib/config_reference.lua):
-- key, type, default, allowed values or range, environment variable and meaning.
-- Usage: gen-config-reference [--check] [--out path]   (default website/en/reference/configuration-keys.md)
-- The page is git-ignored, like the code reference of gen-reference: the website workflow generates it before the
-- site build. `--check` writes nothing: it fails when a declared key has no row in the specification, a row names a
-- key that is not declared, or the declaration cannot be read, and, when the page exists, when it is out of date.
local config_reference = require("lib.config_reference")
local generated_page = require("lib.generated_page")

local TASK, OUT = "gen-config-reference", "website/en/reference/configuration-keys.md"
local SOURCES = {
  declaration = "packages/config/src/hecate/config/declaration.lua",
  load = "packages/config/src/hecate/config/load.lua",
  specification = "docs/architecture/configuration.md",
}

local function absolute(root, path)
  if path:find("^/") or path:find("^%a:[/\\]") then return path end
  return root .. "/" .. path
end

return {
  description = "generate the configuration keys reference page from the config declarations (--check to verify only)",
  run = function(ctx)
    local options, usage = generated_page.arguments(ctx.args, TASK, OUT)
    if not options then return { ok = false, problems = { usage } } end
    local texts, problems = {}, {}
    for name, path in pairs(SOURCES) do
      texts[name] = generated_page.read(ctx.root .. "/" .. path)
      if not texts[name] then problems[#problems + 1] = path .. ": cannot be read" end
    end
    table.sort(problems)
    if #problems > 0 then return { ok = false, problems = problems } end
    local model = config_reference.build(texts)
    problems = model.problems
    local state = "not written"
    if #problems == 0 then
      local page_problems
      state, page_problems = generated_page.apply(absolute(ctx.root, options.out), options.out,
        config_reference.render(model), { check = options.check, task = TASK, is_generated = config_reference.is_generated })
      for _, p in ipairs(page_problems) do problems[#problems + 1] = p end
    end
    local keys = {}
    for i, key in ipairs(model.keys) do
      keys[i] = {
        key = key.key, type = key.type, default = key.default, allowed = key.allowed,
        variable = key.variable, files_only = key.files_only == true, description = key.description,
      }
    end
    return {
      ok = #problems == 0,
      problems = problems,
      output = ("%s: %d keys (%s)"):format(options.out, #model.keys,
        state == "absent" and "absent: not generated here, sources checked" or state),
      data = { page = options.out, state = state, prefix = model.prefix, keys = keys },
    }
  end,
}
