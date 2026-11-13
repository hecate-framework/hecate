-- gen-error-codes: the "Error codes" reference page (ADR 0018: every error class and code is documented), from the
-- error classes declared in packages/*/src, read as files (tools/lib/error_codes.lua): code, class, package, parent,
-- the first sentence of the LuaLS description, and the `context.reason` values each class documents.
-- Usage: gen-error-codes [--check] [--out path]   (default website/en/reference/error-codes.md)
-- The page is git-ignored, like the code reference of gen-reference: the website workflow generates it before the
-- site build. `--check` writes nothing: it fails when the sources cannot be read into a page (a code declared twice,
-- a parent that is not an error class) and, when the page exists, when it is out of date. A class without an
-- annotation, or whose documented reasons cannot be extracted, is a warning.
local util = require("lib.util")
local error_codes = require("lib.error_codes")
local generated_page = require("lib.generated_page")

local TASK, OUT = "gen-error-codes", "website/en/reference/error-codes.md"

local function absolute(root, path)
  if path:find("^/") or path:find("^%a:[/\\]") then return path end
  return root .. "/" .. path
end

return {
  description = "generate the error codes reference page from the error classes of the packages (--check to verify only)",
  run = function(ctx)
    local options, usage = generated_page.arguments(ctx.args, TASK, OUT)
    if not options then return { ok = false, problems = { usage } } end
    local files = {}
    for _, name in ipairs(util.list_dir(ctx.root .. "/packages")) do
      local src = ("%s/packages/%s/src"):format(ctx.root, name)
      if util.is_dir(src) then
        for _, path in ipairs(util.walk(src, ".lua")) do
          files[#files + 1] = { path = path:sub(#ctx.root + 2), text = generated_page.read(path) or "" }
        end
      end
    end
    local model = error_codes.build(files)
    local problems = model.problems
    local state = "not written"
    if #problems == 0 then
      local page_problems
      state, page_problems = generated_page.apply(absolute(ctx.root, options.out), options.out,
        error_codes.render(model), { check = options.check, task = TASK, is_generated = error_codes.is_generated })
      for _, p in ipairs(page_problems) do problems[#problems + 1] = p end
    end
    local classes, with_reasons = {}, 0
    for i, class in ipairs(model.classes) do
      local reasons = {}
      for j, reason in ipairs(class.reasons or {}) do reasons[j] = reason.name end
      if class.reasons then with_reasons = with_reasons + 1 end
      classes[i] = {
        code = class.code, class = class.type or class.name, package = "hecate." .. class.package,
        parent = class.parent, description = class.summary, file = class.file,
        reasons = reasons, reasons_from = class.reasons_from,
      }
    end
    local lines = {}
    for _, w in ipairs(model.warnings) do lines[#lines + 1] = "warning: " .. w end
    lines[#lines + 1] = ("%s: %d classes, %d with reasons (%s)"):format(options.out, #model.classes, with_reasons,
      state == "absent" and "absent: not generated here, sources checked" or state)
    return {
      ok = #problems == 0,
      problems = problems,
      output = table.concat(lines, "\n"),
      data = { page = options.out, state = state, classes = classes, warnings = model.warnings },
    }
  end,
}
