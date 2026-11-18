-- Builds the documentation site of this example with `hecate.doc`:
--   lua examples/hello/build_docs.lua [out]
-- Run it from the repository root. The site goes to `docs/dist` by default
-- (git-ignored). The sources are `docs/en/*.md`, `docs/public/` and
-- `docs/site.lua`; see the README of the example.
global <const> _VERSION, arg, package, io, os, require, pcall, tostring, ipairs

local script = arg[0]:gsub("\\", "/")
local here = script:match("^(.*)/[^/]*$") or "."
local root = here .. "/../.."
for _, name in ipairs({ "doc", "core", "reactor", "json", "schema", "openapi", "unicode", "unicode-data" }) do
  local base = root .. "/packages/" .. name .. "/src/"
  package.path = base .. "?.lua;" .. base .. "?/init.lua;" .. package.path
end
-- The project-local LuaRocks tree (`luv`, built native modules).
do
  local version = _VERSION:match("%d+%.%d+")
  local tree = root .. "/.hecate/rocks"
  package.path = tree .. "/share/lua/" .. version .. "/?.lua;" .. package.path
  package.cpath = tree .. "/lib/lua/" .. version .. "/?.so;" .. tree .. "/lib/lua/" .. version
    .. "/?.dll;" .. package.cpath
end

local doc = require("hecate.doc")
local project = require("hecate.doc.project")
local reactor = require("hecate.reactor")

local source = here .. "/docs"
local out = arg[1] or (source .. "/dist")

local ok, report = pcall(reactor.run, function()
  local fs = doc.SystemFileSystem()
  return project.build({
    config = doc.load_config(source .. "/site.lua", fs),
    source = source,
    out = out,
    fs = fs,
    clean = true,
    strict = true,
  })
end)
if not ok then
  io.stderr:write(tostring(report), "\n")
  os.exit(1)
end
io.stdout:write(("hello docs: %d files in %s\n"):format(report.files, out))
