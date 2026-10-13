-- Builds a documentation site with hecate.doc. Usage:
--   lua packages/doc/bin/build.lua [source] [--config file] [--out dir] [--base /path/]
--                                  [--clean] [--strict] [--no-git-dates]
-- `source` is the content root (default `website`): one directory per locale, optionally
-- `public/`. The configuration defaults to `<source>/site.lua`, the output to `<source>/dist`.
-- This is the bootstrap entry point until `hecate doc build` exists (automation.md); it
-- reads the file system through `hecate.doc.SystemFileSystem` (OQ-33).
-- Exit codes: 0 built, 1 build failed or, with --strict, problems were found, 2 usage error.
global <const> arg, io, os, package, require, print, pcall, tostring, ipairs, pairs, table

local script = arg[0]:gsub("\\", "/")
local here = script:match("^(.*)/[^/]*$") or "."
-- Monorepo checkout: the sources of this package and of its dependencies. An installed
-- rock has them on the path already.
for _, package_name in ipairs({ "doc", "core", "json", "schema", "openapi" }) do
  local base = here .. "/../../" .. package_name .. "/src/"
  package.path = base .. "?.lua;" .. base .. "?/init.lua;" .. package.path
end
local base = here .. "/../src/"
package.path = base .. "?.lua;" .. base .. "?/init.lua;" .. package.path

local doc = require("hecate.doc")

local function usage(stream)
  stream:write("usage: lua build.lua [source] [--config file] [--out dir] [--base /path/] "
    .. "[--clean] [--strict] [--no-git-dates]\n")
end

local options = { source = "website" }
local flags = {}
do
  local i = 1
  while i <= #arg do
    local value = arg[i]
    if value == "--config" or value == "--out" or value == "--base" then
      options[value:sub(3)] = arg[i + 1]
      if not arg[i + 1] then usage(io.stderr) os.exit(2) end
      i = i + 1
    elseif value:sub(1, 2) == "--" then
      flags[value:sub(3)] = true
    elseif value == "-h" then
      usage(io.stdout)
      os.exit(0)
    else
      options.source = value
    end
    i = i + 1
  end
end
for name in pairs(flags) do
  if name ~= "clean" and name ~= "strict" and name ~= "no-git-dates" and name ~= "help" then
    io.stderr:write("unknown option --" .. name .. "\n")
    usage(io.stderr)
    os.exit(2)
  end
end
if flags.help then usage(io.stdout) os.exit(0) end

local is_windows = package.config:sub(1, 1) == "\\"

local function quote(path)
  if is_windows then return '"' .. path:gsub("/", "\\"):gsub('"', '""') .. '"' end
  return "'" .. path:gsub("'", "'\\''") .. "'"
end

--- Date of the last commit that touched a file (`git log --format=%cs`), or nil.
local function git_date(path)
  local directory, name = path:match("^(.*)/([^/]*)$")
  if not directory then directory, name = ".", path end
  local command = ("git -C %s log -1 --format=%%cs -- %s 2>%s"):format(quote(directory), quote(name),
    is_windows and "nul" or "/dev/null")
  if is_windows then command = '"' .. command .. '"' end
  local pipe = io.popen(command, "r")
  if not pipe then return nil end
  local output = pipe:read("a")
  pipe:close()
  return output:match("^(%d%d%d%d%-%d%d%-%d%d)")
end

local function run()
  local fs = doc.SystemFileSystem()
  local config = doc.load_config(options.config or (options.source .. "/site.lua"), fs)
  if options.base then config.base = options.base end
  return doc.build({
    config = config,
    source = options.source,
    out = options.out or (options.source .. "/dist"),
    fs = fs,
    clean = flags.clean,
    strict = flags.strict,
    last_updated = (not flags["no-git-dates"]) and git_date or nil,
  })
end

local ok, report = pcall(run)
if not ok then
  io.stderr:write(tostring(report), "\n")
  os.exit(1)
end
for _, problem in ipairs(report.problems) do io.stderr:write("warning: ", problem, "\n") end
local locales = {}
for code, entry in pairs(report.locales) do
  locales[#locales + 1] = ("%s: %d pages (%d from the default locale)"):format(code, entry.pages, entry.fallbacks)
end
table.sort(locales)
print(("hecate.doc: %d files, %d bytes; %s"):format(report.files, report.bytes, table.concat(locales, "; ")))
os.exit(0)
