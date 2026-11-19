-- The guard of the writes of a build: a file is never written through a symbolic link. A link at the place of a generated page
-- or of an output file would make the write truncate or create the file it points to (a dangling `docs/en/configuration.md`
-- that points to `~/.ssh/authorized_keys`), and a link at the place of a directory would send the files below it elsewhere.
-- Checked with the semantics of `lstat`: the entry itself, never what it points to (`FileSystem.is_link`).
global <const> require, ipairs, error

local errors = require("hecate.doc.errors")
local paths = require("hecate.doc.internal.paths")

local M = {}

--- A function `check(path)` for the writes below `boundary`: it raises `hecate.doc.BuildError` when `path`, or a directory
--- between `boundary` (excluded: it is the directory the caller chose) and `path`, is a symbolic link. A file system without
--- `is_link` has no links and is never refused. Each directory is looked up once.
---@param fs hecate.doc.FileSystem
---@param boundary string
---@return fun(path: string)
function M.guard(fs, boundary)
  local checked = {}
  return function(path)
    if not fs.is_link then return end
    local segments = paths.below(boundary, path)
    local prefix, count = boundary, segments and #segments or 0
    if count == 0 then
      -- Not below the boundary: only the target itself is looked at.
      if fs:is_link(path) then
        error(errors.BuildError({
          message = ("doc: refusing to write %s: it is a symbolic link; remove it or write elsewhere"):format(path),
          context = { path = path },
        }), 0)
      end
      return
    end
    for index, segment in ipairs(segments --[[@as string[] ]]) do
      prefix = prefix:gsub("/+$", "") .. "/" .. segment
      local target = index == count
      if target or not checked[prefix] then
        if fs:is_link(prefix) then
          error(errors.BuildError({
            message = ("doc: refusing to write %s: %s is a symbolic link; remove it or write elsewhere"):format(path, prefix),
            context = { path = path },
          }), 0)
        end
        if not target then checked[prefix] = true end
      end
    end
  end
end

return M
