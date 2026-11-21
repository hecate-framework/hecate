-- Builds the documentation site of this example with `hecate.doc`:
--   lua examples/hello/build_docs.lua [out]
-- Run it from the repository root. The site goes to `docs/dist` by default
-- (git-ignored), as one site per audience: `docs/dist/maintainer/`. The
-- sources are the maintainer tree `docs/maintainer/en/*.md` and
-- `docs/maintainer/public/`, and `docs/site.lua`; see the example README.
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
local reactor = require("hecate.reactor")

-- The example follows the conventional layout of a project: the guides of an
-- audience in `docs/<audience>/` (only `docs/maintainer/`: the default builds
-- the maintainer tree), site configuration in `docs/site.lua`, sites in
-- `docs/dist/<audience>/`.
-- Only the project directory is given; an output directory of the command
-- line is relative to it unless it is absolute.
local output_dir = arg[1] or "docs/dist"

local ok, report = pcall(reactor.run, function()
  return doc.generate_project_documentation({
    project_dir = here,
    output_dir = output_dir,
    clean_output_dir = true,
    fail_on_problems = true,
  })
end)
if not ok then
  io.stderr:write(tostring(report), "\n")
  os.exit(1)
end
io.stdout:write(("hello docs: %d files in %s\n"):format(report.files, output_dir))
