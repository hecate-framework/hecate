-- Task runner: lua tools/run.lua <task> [args] [--json]
-- Tasks live in tools/tasks/<name>.lua (file name uses underscores; the task name uses
-- hyphens) and export { description = string, run = function(args) -> report }.
-- A report is { ok = boolean, problems = { string... } }.
-- Exit codes: 0 success, 1 task failure, 2 usage error.

local script = arg[0]:gsub("\\", "/")
local tools_dir = script:match("^(.*)/[^/]*$") or "."
local root = tools_dir .. "/.."
package.path = tools_dir .. "/?.lua;" .. tools_dir .. "/lib/?.lua;" .. package.path

local util = require("lib.util")

local function task_names()
  local names = {}
  for _, f in ipairs(util.list_dir(tools_dir .. "/tasks")) do
    local n = f:match("^(.+)%.lua$")
    if n then names[#names + 1] = (n:gsub("_", "-")) end
  end
  return names
end

local function load_task(name)
  local ok, task = pcall(require, "tasks." .. name:gsub("-", "_"))
  if ok then return task end
  return nil, task
end

local function usage(out)
  out:write("usage: lua tools/run.lua <task> [args] [--json]\n       lua tools/run.lua --list\n")
end

local args, json = {}, false
for _, a in ipairs(arg) do
  if a == "--json" then json = true else args[#args + 1] = a end
end

if args[1] == nil or args[1] == "--help" or args[1] == "-h" then
  usage(io.stdout)
  os.exit(args[1] == nil and 2 or 0)
end

if args[1] == "--list" then
  for _, name in ipairs(task_names()) do
    local task = load_task(name)
    print(("%-28s %s"):format(name, task and task.description or ""))
  end
  os.exit(0)
end

local name = table.remove(args, 1)
local task, err = load_task(name)
if not task then
  io.stderr:write(("unknown task '%s'\n"):format(name))
  if err and not tostring(err):find("module 'tasks%.") then io.stderr:write(tostring(err), "\n") end
  usage(io.stderr)
  os.exit(2)
end

if args[1] == "--help" then
  print(task.description)
  os.exit(0)
end

local report = task.run({ root = root, args = args })
if json then
  print(util.json({ task = name, ok = report.ok, problems = report.problems }))
else
  for _, p in ipairs(report.problems) do io.stderr:write(p, "\n") end
  print(("%s: %s"):format(name, report.ok and "ok" or ("%d problem(s)"):format(#report.problems)))
end
os.exit(report.ok and 0 or 1)
