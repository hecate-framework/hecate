-- Writing and checking a generated website page (gen-error-codes, gen-config-reference). The pages live in
-- website/en/reference/ and are git-ignored: the website workflow generates them before the site build, like the
-- code reference of gen-reference. A file without the generator's marker is never overwritten.
local util = require("lib.util")

local M = {}

local function read(path)
  local f = io.open(path, "rb")
  if not f then return nil end
  local s = f:read("a")
  f:close()
  return s
end

--- Writes `content` to `path`, or with `check` compares them. Returns the state and the problems.
--- States: `written`, `unchanged`, `up to date`, `absent` (check of a page that is not generated here).
---@param path string  absolute path of the page
---@param relative string  repository-relative path (messages)
---@param content string
---@param options { check: boolean, task: string, is_generated: fun(content: string): boolean }
---@return string state, string[] problems
function M.apply(path, relative, content, options)
  local old = read(path)
  if old ~= nil and not options.is_generated(old) then
    return "kept", { ("%s does not carry the marker of %s; it was left alone (remove it to generate the page)"):format(
      relative, options.task) }
  end
  if options.check then
    if old == nil then return "absent", {} end
    if old ~= content then return "stale", { ("%s is out of date; run lua tools/run.lua %s"):format(relative, options.task) } end
    return "up to date", {}
  end
  if old == content then return "unchanged", {} end
  local directory = path:match("^(.*)/[^/]*$")
  if directory and not util.is_dir(directory) then util.mkdir(directory) end
  local f, err = io.open(path, "wb")
  if not f then return "failed", { ("%s: %s"):format(relative, tostring(err)) } end
  f:write(content)
  f:close()
  return "written", {}
end

--- Parses `[--check] [--out path]`. Returns the options, or nil and a usage message.
---@param args string[]
---@param task string
---@param default_out string  repository-relative
---@return { check: boolean, out: string }?, string?
function M.arguments(args, task, default_out)
  local options = { check = false, out = default_out }
  local i = 1
  while i <= #args do
    local a = args[i]
    if a == "--check" then options.check = true
    elseif a == "--out" and args[i + 1] then
      options.out = args[i + 1]
      i = i + 1
    else
      return nil, ("usage: %s [--check] [--out path]"):format(task)
    end
    i = i + 1
  end
  return options
end

M.read = read

return M
