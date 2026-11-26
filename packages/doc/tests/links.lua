-- Test helper (not a test): checks the references of a built site. A built site opens from the file system (file://) and from
-- any static host (OQ-148), so every local reference of every page and every stylesheet must be a path relative to the file
-- that holds it, and must lead to a file of the output. Loaded with `dofile` by the tests of the package.
global <const> pairs, ipairs, table, string, tonumber

local M = {}

local function decode(text)
  return (text:gsub("%%(%x%x)", function(hex) return string.char(tonumber(hex, 16)) end))
end

local function unescape(text)
  return (text:gsub("&quot;", '"'):gsub("&#39;", "'"):gsub("&lt;", "<"):gsub("&gt;", ">"):gsub("&amp;", "&"))
end

--- Resolves `reference` against the directory of `from` (a path below the root of the output); returns the path below the
--- root, or nil when the reference climbs above the root.
local function resolve(from, reference)
  local parts = {}
  for segment in (from:match("^(.*)/[^/]*$") or ""):gmatch("[^/]+") do parts[#parts + 1] = segment end
  for segment in reference:gmatch("[^/]+") do
    if segment == ".." then
      if #parts == 0 then return nil end
      parts[#parts] = nil
    elseif segment ~= "." then
      parts[#parts + 1] = segment
    end
  end
  return table.concat(parts, "/")
end

--- Checks one reference found in `file`; appends a problem when it is root-relative, climbs out of the output or leads to
--- no file. Returns true when the reference was a local one (checked).
local function check_reference(files, file, kind, value, problems)
  local reference = unescape(value)
  if reference == "" or reference:find("^#") or reference:find("^//") or reference:find("^%a[%w+.%-]*:") then return false end
  if reference:find("^/") then
    problems[#problems + 1] = ("%s: root-relative %s %q"):format(file, kind, reference)
    return true
  end
  local path = reference:match("^([^#?]*)")
  local target = resolve(file, decode(path))
  if target == nil then
    problems[#problems + 1] = ("%s: %s %q climbs above the root of the output"):format(file, kind, reference)
  elseif files[target] == nil then
    problems[#problems + 1] = ("%s: %s %q leads to %q, which is no file of the output"):format(file, kind, reference, target)
  end
  return true
end

--- Checks every local reference of the HTML pages and the stylesheets of a built site: `href` and `src` attributes of the
--- tags (text is never read: a page that shows a link in a code block is not a link), the `url=` of a meta refresh, the
--- paths of the script configuration (`doc-config`: `index` and `root`) and the `url(...)` of the stylesheets. A reference with
--- a scheme (`https:`, `data:`), a protocol-relative one and a fragment alone are not local.
---@param files table<string, string>  path below the root of the output (`en/index.html`) mapped to its content
---@return string[] problems
---@return integer checked  the number of local references checked (a test asserts it is not zero)
function M.check(files)
  local problems, checked = {}, 0
  local paths = {}
  for path in pairs(files) do paths[#paths + 1] = path end
  table.sort(paths)
  for _, file in ipairs(paths) do
    local text = files[file]
    if file:find("%.html$") then
      for name, attributes in text:gmatch("<(%a[%w%-]*)(%s[^>]*)>") do
        for attribute, value in attributes:gmatch('%s([%w%-:]+)="([^"]*)"') do
          if attribute == "href" or attribute == "src" then
            if check_reference(files, file, name .. " " .. attribute, value, problems) then checked = checked + 1 end
          elseif attribute == "content" and name == "meta" then
            local target = value:match("^%d+;%s*url=(.*)$")
            if target and check_reference(files, file, "meta refresh", target, problems) then checked = checked + 1 end
          end
        end
      end
      local configuration = text:match('<script type="application/json" id="doc%-config">(.-)</script>')
      if configuration then
        local index = configuration:match('"index":"([^"]*)"')
        if index and check_reference(files, file, "search index", index, problems) then checked = checked + 1 end
        local root = configuration:match('"root":"([^"]*)"')
        -- The root is a prefix: the theme stylesheet is found below it.
        if root and not root:find("^%a[%w+.%-]*:") and check_reference(files, file, "root", root .. "assets/theme.css", problems) then
          checked = checked + 1
        end
      end
    elseif file:find("%.css$") then
      for value in text:gmatch("url%(%s*[\"']?([^\"')]-)[\"']?%s*%)") do
        if check_reference(files, file, "css url", value, problems) then checked = checked + 1 end
      end
    end
  end
  return problems, checked
end

--- The files of a memory file system below `prefix` (`o/`), keyed by the path below it.
---@param memory table  a `hecate.doc.MemoryFileSystem`
---@param prefix string
---@return table<string, string>
function M.files_below(memory, prefix)
  local out = {}
  for path, data in pairs(memory.files) do
    if path:sub(1, #prefix) == prefix then out[path:sub(#prefix + 1)] = data end
  end
  return out
end

return M
