-- Portable names: what a file of the site may be called so that the output can be copied, served and unpacked on Linux,
-- macOS and Windows. One function, `portable_name`, is applied to every name the builder reads or writes: page ids,
-- the files next to the guides (images and so on), the files of `public/` and the files the site configuration names
-- (`logo_path`, `favicon_path`, `stylesheet_path`).
--
-- It applies, to every segment of the path:
--   - the naming rules of Windows (`page_id.windows_problem`: reserved device names such as `aux.png` and `con/x.svg`,
--     reserved characters, a trailing dot or space; Microsoft, "Naming Files, Paths, and Namespaces");
--   - Normalization Form C (Unicode Standard 3.11, UAX #15), so that a tree authored on macOS (NFD) and one authored
--     on Linux name the same file the same way;
--   - the case-fold KEY (`case_fold`), the name two files must not share: `Img/a.svg` and `img/a.svg` are one file on a
--     case-insensitive file system;
--   - the length limits: a segment is at most 255 bytes (ext4, APFS and NTFS limit a name to 255 bytes or UTF-16 code
--     units, and a byte count is the safe side of both), and an output path of 260 characters or more does not open on
--     Windows without long-path support (MAX_PATH is 260 characters *including* the terminating NUL; Microsoft,
--     "Maximum Path Length Limitation").
--
-- A `Namespace` holds the output paths of one site and finds the collisions between them: the same key (two files
-- that differ only by case or by normalisation), and a file whose path is a directory of another (`a` and `a/b`).
global <const> table, ipairs, require, utf8

local core = require("hecate.core")
local case_fold = require("hecate.doc.internal.case_fold")
local page_id = require("hecate.doc.internal.page_id")

local M = {}

--- The longest name of one path segment, in bytes.
M.MAX_SEGMENT_BYTES = 255

--- The longest output path, in characters, that opens on Windows without long-path support (MAX_PATH 260 minus the
--- terminating NUL).
M.MAX_PATH_CHARACTERS = 259

--- The comparison key of a path: composed (NFC), case-folded, composed again (the canonical caseless match of the
--- Unicode Standard 3.13, D145, folds can leave a string uncomposed).
---@param path string
---@return string
function M.key(path)
  return page_id.nfc(case_fold.fold(page_id.nfc(path)))
end

--- The length of a path as Windows counts it: UTF-16 code units (a code point above U+FFFF is two). A path that is not
--- valid UTF-8 is counted in bytes.
---@param path string
---@return integer
function M.length(path)
  if not utf8.len(path) then return #path end
  local units = 0
  for _, code in utf8.codes(path) do units = units + (code > 0xFFFF and 2 or 1) end
  return units
end

--- The problem of an output path (`<output_dir>/...`) that does not open on Windows without long-path support, or nil.
---@param output_path string
---@return string?
function M.path_limit_problem(output_path)
  local length = M.length(output_path)
  if length <= M.MAX_PATH_CHARACTERS then return nil end
  return ("the output path %s is %d characters long, more than the %d that open on Windows without long-path support (MAX_PATH): shorten the page id or the output directory"):format(
    output_path, length, M.MAX_PATH_CHARACTERS)
end

---@class hecate.doc.PortableName
---@field name string  the path in NFC: the name the output uses
---@field key string  the case-fold key: two paths with the same key are one file on a case-insensitive file system
---@field problem? string  why the path is not a valid name on Windows (a refusal: the site cannot be copied there)
---@field limits string[]  the length limits the path goes beyond (problems: reported, and errors under `fail_on_problems`)

--- Checks one relative path (segments joined by `/`, without a leading `/`).
---@param relative_path string
---@return hecate.doc.PortableName
function M.portable_name(relative_path)
  local name = page_id.nfc(relative_path)
  local limits = {}
  for segment in name:gmatch("[^/]+") do
    if #segment > M.MAX_SEGMENT_BYTES then
      limits[#limits + 1] = ("the segment %q is %d bytes long, more than the limit of %d bytes of a file name"):format(
        #segment > 40 and (segment:sub(1, 37) .. "...") or segment, #segment, M.MAX_SEGMENT_BYTES)
    end
  end
  return { name = name, key = M.key(name), problem = page_id.windows_problem(relative_path), limits = limits }
end

--- Whether a file name is a Markdown page (`.md`, in any case: on a case-insensitive file system `README.MD` is the
--- file `readme.md`, and a page whose suffix is spelt in upper case must not be a page on one platform and a plain file
--- on another).
---@param name string
---@return boolean
function M.is_markdown(name)
  return #name > 3 and name:sub(-3):lower() == ".md"
end

---@class hecate.doc.NamespaceEntry
---@field path string
---@field label string
---@field kind? string

---@class hecate.doc.Namespace
---@field private _files table<string, hecate.doc.NamespaceEntry>
---@field private _directories table<string, hecate.doc.NamespaceEntry>
local Namespace = core.class("PortableNamespace")

function Namespace:init()
  self._files = {} ---@type table<string, hecate.doc.NamespaceEntry>
  self._directories = {} ---@type table<string, hecate.doc.NamespaceEntry>
end

--- Creates an empty namespace of output paths.
---@return hecate.doc.Namespace
function M.namespace()
  return Namespace()
end

--- Records the output file `path` (`label` names its source in a message). Returns nil when it is free, else the kind
--- of collision and the file it collides with: `"same"` (the same path), `"case"` (the same key, so one file on a
--- case-insensitive file system or after normalisation), or `"directory"` (the path is a directory of another file or
--- a directory is where this file is). A refused path is not recorded. `source_kind` is kept with the path and given
--- back in `other.kind` (the caller tells a page from a file).
---@param path string
---@param label string
---@param source_kind? string
---@return ("same"|"case"|"directory")? kind
---@return hecate.doc.NamespaceEntry? other
function Namespace:claim(path, label, source_kind)
  local key = M.key(path)
  local existing = self._files[key]
  if existing then return existing.path == path and "same" or "case", existing end
  if self._directories[key] then return "directory", self._directories[key] end
  local keys, names = {}, {}
  for segment in key:gmatch("[^/]+") do keys[#keys + 1] = segment end
  for segment in path:gmatch("[^/]+") do names[#names + 1] = segment end
  local prefixes = {}
  for index = 1, #keys - 1 do
    local prefix_key = table.concat(keys, "/", 1, index)
    if self._files[prefix_key] then return "directory", self._files[prefix_key] end
    prefixes[#prefixes + 1] = { prefix_key, table.concat(names, "/", 1, index) }
  end
  for _, prefix in ipairs(prefixes) do
    self._directories[prefix[1]] = self._directories[prefix[1]] or { path = prefix[2], label = label, kind = source_kind }
  end
  self._files[key] = { path = path, label = label, kind = source_kind }
  return nil
end

core.finalise(Namespace)

return M
