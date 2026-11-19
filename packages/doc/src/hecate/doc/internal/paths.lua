-- Path strings, as pure functions (no file access), so that the rules of Windows are tested on every platform.
--
-- `hecate.doc` takes directories as option strings from the user. `\` is read as a separator at the entry points
-- (`build`, `generate_project_documentation`; `SystemFileSystem` on Windows only, where it is one): everything below
-- them works with `/`. A path is compared lexically: no link is resolved, no current directory is looked up, so two
-- paths of different forms (one absolute, one relative) are not comparable and are never reported as overlapping.
global <const> require, string, table, package, ipairs

local M = {}

--- True when the platform separates paths with `\` (Windows).
---@return boolean
function M.is_windows()
  return package.config:sub(1, 1) == "\\"
end

--- Replaces every `\` by `/`.
---@param path string
---@return string
function M.separators(path)
  return (path:gsub("\\", "/"))
end

--- Whether `path` is absolute: it starts with a separator (`/`, or `\` which names the root of the current drive or a
--- UNC path) or with a drive and a separator (`C:/`, `C:\`). A drive without a separator (`C:file`) is relative to the
--- current directory of that drive: it is not absolute, see `is_drive_relative`.
---@param path string
---@return boolean
function M.is_absolute(path)
  return path:find("^[/\\]") ~= nil or path:find("^%a:[/\\]") ~= nil
end

--- Whether `path` is a drive-relative path of Windows (`C:file`, `C:`): not the same file in every directory, so the
--- options refuse it. Only where the rule applies: on another platform `v:1` is a plain relative name, unless
--- `windows` says otherwise (the argument is for the tests).
---@param path string
---@param windows? boolean  default: the running platform
---@return boolean
function M.is_drive_relative(path, windows)
  if windows == nil then windows = M.is_windows() end
  if not windows then return false end
  return path:find("^%a:[^/\\]") ~= nil or path:find("^%a:$") ~= nil
end

--- Splits a path into its root (`""`, `/`, `//server/share/`, `C:/`) and its normal segments: `.` and empty segments are
--- dropped, `..` removes the segment before it (below an absolute root it is dropped, in a relative path it stays when
--- nothing is left to remove).
---@param path string
---@return string root
---@return string[] segments
function M.split(path)
  path = M.separators(path)
  local root = ""
  local unc, server, share = path:match("^(//)([^/]+)/([^/]+)")
  if unc then
    root = "//" .. server .. "/" .. share .. "/"
    path = path:sub(#root + 1)
  elseif path:find("^%a:/") then
    root = path:sub(1, 3)
    path = path:sub(4)
  elseif path:find("^/") then
    root = "/"
  end
  local segments = {}
  for segment in path:gmatch("[^/]+") do
    if segment == ".." then
      if #segments > 0 and segments[#segments] ~= ".." then
        segments[#segments] = nil
      elseif root == "" then
        segments[#segments + 1] = ".."
      end
    elseif segment ~= "." then
      segments[#segments + 1] = segment
    end
  end
  return root, segments
end

--- The normal form of a path: separators `/`, no `.`, no empty segment, `..` folded, no trailing separator; `.` for
--- the current directory.
---@param path string
---@return string
function M.normalise(path)
  local root, segments = M.split(path)
  local joined = table.concat(segments, "/")
  if joined == "" then return root == "" and "." or root end
  return root .. joined
end

--- Whether `path` is the root of a file system: `/`, a drive root (`C:/`), a UNC root (`//server`, `//server/share`) or
--- empty after normalisation.
---@param path string
---@return boolean
function M.is_root(path)
  path = M.separators(path)
  if path:find("^//[^/]*/?[^/]*/*$") then return true end
  local root, segments = M.split(path)
  return root ~= "" and #segments == 0
end

--- `directory` followed by `path`; an absolute `path` is kept, and `.` or an empty directory adds nothing.
---@param directory string
---@param path string
---@return string
function M.resolve(directory, path)
  if M.is_absolute(path) or directory == "." or directory == "" then return path end
  return (directory:gsub("[/\\]+$", "")) .. "/" .. path
end

-- Root, number of leading `..` and the other segments, case-folded (a case-insensitive file system, Windows and
-- macOS, makes `Docs` and `docs` one directory; refusing a pair that differs only by case is the safe side on the
-- others).
local function parts_of(path)
  local root, segments = M.split(path)
  local ups = 0
  while segments[ups + 1] == ".." do ups = ups + 1 end
  local rest = {}
  for index = ups + 1, #segments do rest[#rest + 1] = segments[index]:lower() end
  return root:lower(), ups, rest
end

--- How `path` lies relative to `other`, lexically: `"same"`, `"inside"` (below `other`), `"contains"` (an ancestor of
--- `other`), or nil when unrelated or not comparable (an absolute and a relative path, two relative paths that climb
--- out of the current directory by a different number of levels and name something after it).
---@param path string
---@param other string
---@return "same"|"inside"|"contains"|nil
function M.relation(path, other)
  local root_a, ups_a, rest_a = parts_of(path)
  local root_b, ups_b, rest_b = parts_of(other)
  if root_a ~= root_b then return nil end
  if ups_a ~= ups_b then
    if ups_a > ups_b then return #rest_a == 0 and "contains" or nil end
    return #rest_b == 0 and "inside" or nil
  end
  local common = 0
  while common < #rest_a and common < #rest_b and rest_a[common + 1] == rest_b[common + 1] do common = common + 1 end
  if common == #rest_a and common == #rest_b then return "same" end
  if common == #rest_b then return "inside" end
  if common == #rest_a then return "contains" end
  return nil
end

--- The segments of `path` below `base`, or nil when `path` is not below `base`.
---@param base string
---@param path string
---@return string[]?
function M.below(base, path)
  local root_base, base_segments = M.split(base)
  local root_path, path_segments = M.split(path)
  if root_base ~= root_path or #path_segments < #base_segments then return nil end
  for index, segment in ipairs(base_segments) do
    if path_segments[index] ~= segment then return nil end
  end
  return table.move(path_segments, #base_segments + 1, #path_segments, 1, {})
end

return M
