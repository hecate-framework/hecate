-- Generates the code reference of the packages into the site sources. Usage:
--   lua packages/doc/bin/reference.lua [--root dir] [--out dir] [--packages a,b,c] [--since version]
-- `root` is the repository root (default: the repository this script is in), `out` the English
-- content root (default `<root>/website/en`). Needs `lua-language-server` on the path; without
-- it nothing is written and the exit code is 0 (the caller decides whether that is acceptable:
-- `tools/run.lua gen-reference` reports it as a skip). Exit codes: 0 done or skipped, 1 failed,
-- 2 usage error. This is the bootstrap entry point until `hecate doc` exists (automation.md).
global <const> arg, io, os, package, require, print, pcall, tostring, ipairs, pairs, table
global <const> string

local script = arg[0]:gsub("\\", "/")
local here = script:match("^(.*)/[^/]*$") or "."
for _, package_name in ipairs({ "doc", "core", "json", "schema", "openapi" }) do
  local base = here .. "/../../" .. package_name .. "/src/"
  package.path = base .. "?.lua;" .. base .. "?/init.lua;" .. package.path
end

local doc = require("hecate.doc")
local reference_site = require("hecate.doc.reference_site")

local function usage(stream)
  stream:write("usage: lua reference.lua [--root dir] [--out dir] [--packages a,b,c] [--since version]\n")
end

local options = { root = here .. "/../../.." }
do
  local i = 1
  while i <= #arg do
    local value = arg[i]
    if value == "--root" or value == "--out" or value == "--packages" or value == "--since" then
      if not arg[i + 1] then usage(io.stderr) os.exit(2) end
      if value == "--packages" then
        options.packages = {}
        for name in arg[i + 1]:gmatch("[^,]+") do options.packages[#options.packages + 1] = name end
      else
        options[value:sub(3)] = arg[i + 1]
      end
      i = i + 1
    elseif value == "-h" or value == "--help" then
      usage(io.stdout)
      os.exit(0)
    else
      usage(io.stderr)
      os.exit(2)
    end
    i = i + 1
  end
end
options.out = options.out or (options.root .. "/website/en")
options.fs = doc.SystemFileSystem()

local ok, report = pcall(reference_site.run, options)
if not ok then
  io.stderr:write(tostring(report), "\n")
  os.exit(1)
end
for _, problem in ipairs(report.problems) do io.stderr:write("warning: ", problem, "\n") end
if report.skipped then
  print("hecate.doc: skipped: " .. report.skipped)
  os.exit(0)
end
print(("hecate.doc: %d reference pages for %s"):format(report.pages, table.concat(report.packages, ", ")))
os.exit(0)
