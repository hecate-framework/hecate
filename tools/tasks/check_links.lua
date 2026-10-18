-- check-links: internal Markdown links and anchors resolve (external links are not checked).
local util = require("lib.util")
local links = require("lib.links")

local SKIP = { [".git"] = true, [".hecate"] = true, spikes = true, node_modules = true }

local function read(path)
  local f = io.open(path, "rb")
  if not f then return nil end
  local s = f:read("a")
  f:close()
  return s
end

local function collect(root)
  local files = {}
  local function visit(dir, rel)
    for _, name in ipairs(util.list_dir(dir)) do
      if not SKIP[name] then
        local path, r = dir .. "/" .. name, rel == "" and name or rel .. "/" .. name
        if util.is_dir(path) then visit(path, r)
        elseif name:sub(-3) == ".md" then files[#files + 1] = r end
      end
    end
  end
  visit(root, "")
  return files
end

local function normalise(path)
  local parts = {}
  for seg in path:gmatch("[^/]+") do
    if seg == ".." then parts[#parts] = nil elseif seg ~= "." then parts[#parts + 1] = seg end
  end
  return table.concat(parts, "/")
end

return {
  description = "internal Markdown links and anchors resolve",
  run = function(ctx)
    local problems, anchor_cache = {}, {}
    local function anchors_of(rel)
      if not anchor_cache[rel] then anchor_cache[rel] = links.anchors(read(ctx.root .. "/" .. rel) or "") end
      return anchor_cache[rel]
    end
    for _, rel in ipairs(collect(ctx.root)) do
      local dir = rel:match("^(.*)/[^/]*$") or ""
      for _, l in ipairs(links.extract(read(ctx.root .. "/" .. rel) or "")) do
        local target = l.path == "" and rel or normalise((dir ~= "" and dir .. "/" or "") .. l.path:gsub("%%20", " "))
        local at = ("%s:%d"):format(rel, l.line)
        local function exists(path) return util.exists(ctx.root .. "/" .. path) end
        if links.is_ungenerated_reference(target, exists) then
          -- The code reference is generated and git-ignored: the strict build (--reference) checks these links.
        elseif not exists(target) then
          problems[#problems + 1] = ("%s: broken link to '%s'"):format(at, l.path)
        elseif l.fragment and target:sub(-3) == ".md" and not util.is_dir(ctx.root .. "/" .. target)
          and not anchors_of(target)[l.fragment:lower()] then
          problems[#problems + 1] = ("%s: no anchor '#%s' in %s"):format(at, l.fragment, target)
        end
      end
    end
    return { ok = #problems == 0, problems = problems }
  end,
}
