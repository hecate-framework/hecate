-- check-adr-index: docs/adr/README.md lists every ADR with its actual status.
local util = require("lib.util")

local function read(path)
  local f = io.open(path, "rb")
  if not f then return nil end
  local s = f:read("a")
  f:close()
  return s
end

return {
  description = "docs/adr/README.md lists every ADR with its actual status",
  run = function(ctx)
    local problems = {}
    local dir = ctx.root .. "/docs/adr"
    local index = read(dir .. "/README.md")
    if not index then return { ok = false, problems = { "docs/adr/README.md is missing" } } end
    local listed = {}
    for num, file, status in index:gmatch("|%s*%[(%d+)%]%(([^)]+)%)%s*|[^|]*|%s*([^|]-)%s*|") do
      listed[file] = { num = num, status = status }
    end
    for _, f in ipairs(util.list_dir(dir)) do
      local num = f:match("^(%d%d%d%d)%-.+%.md$")
      if num then
        local entry = listed[f]
        if not entry then
          problems[#problems + 1] = ("docs/adr/%s is not listed in docs/adr/README.md"):format(f)
        else
          listed[f] = nil
          local text = read(dir .. "/" .. f) or ""
          local actual = text:match("[Ss]tatus[:%*%s]+([%a]+)")
          local shown = entry.status:match("^(%a+)")
          if actual and shown and actual ~= shown then
            problems[#problems + 1] = ("docs/adr/%s: status is '%s' but the index says '%s'"):format(f, actual, shown)
          end
        end
      end
    end
    for f in pairs(listed) do
      problems[#problems + 1] = ("docs/adr/README.md lists %s, which does not exist"):format(f)
    end
    table.sort(problems)
    return { ok = #problems == 0, problems = problems }
  end,
}
