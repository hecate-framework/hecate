-- The third-party licences page of a project: the rocks of an installed tree (name, version, licence, licence text)
-- and what the generated site bundles (fonts, brand marks, icon, Mermaid), with the licence texts reproduced from
-- the files of the theme (THIRD_PARTY_NOTICES lists the same material). The rocks are read as files of the tree,
-- never through a `luarocks` process, and a rockspec is data of the project: it is never run with the privileges
-- of the build (see `parse_rockspec`).
-- The functions are deterministic: rocks and texts are sorted, and the same tree gives the same page.
global <const> require, type, ipairs, pairs, table, string, tostring, load, utf8, debug, coroutine, math, io, error

local text_helpers = require("hecate.doc.internal.text")

local plain, code, fenced = text_helpers.plain, text_helpers.code, text_helpers.fenced

--- Reads the installed rocks of a tree and writes the third-party licences page.
---@class hecate.doc.licenses
local M = {}

-- Limits: a tree and its rockspecs are data of the project and may be hostile or enormous.
local MAX_ROCKSPEC_BYTES = 256 * 1024
local MAX_TEXT_BYTES = 64 * 1024
local MAX_ROCKS = 2000
local MAX_DEPENDENCIES = 500
local MAX_LICENSE_CHARS = 200
local MAX_INSTRUCTIONS = 1000000

---@class hecate.doc.Rock
---@field name string
---@field version string
---@field license? string  as the rockspec declares it (`description.license`; an SPDX identifier when the rock uses one)
---@field homepage? string
---@field dependencies string[]  names of the rocks it depends on (`lua` excluded)
---@field required_by string[]  names of the selected rocks that depend on it, sorted
---@field text? string  the licence text found in the installed rock
---@field text_file? string  where it was found

---@class hecate.doc.LicensesModel
---@field rocks hecate.doc.Rock[]  sorted by name, then version
---@field problems string[]  what could not be read or resolved, in the order met

---@class hecate.doc.Bundled
---@field name string
---@field use string  what it is used for
---@field license string  SPDX expression
---@field shipped boolean  part of the generated site (false: used to build it only)
---@field text? string  the licence text, when it is reproduced
---@field note? string

local NAME_PATTERN = "^[%w_%.%-]+$"

-- The code of a Lua chunk without its strings and comments (Lua 5.5 manual, 3.1), or nil when a string is not
-- terminated.
local function code_of(text)
  local out, position, length = {}, 1, #text
  while position <= length do
    local char = text:sub(position, position)
    local long = text:match("^%[(=*)%[", position)
    if char == "-" and text:sub(position + 1, position + 1) == "-" then
      local level = text:match("^%[(=*)%[", position + 2)
      if level then
        local _, finish = text:find("]" .. level .. "]", position + 4 + #level, true)
        if not finish then return nil end
        position = finish + 1
      else
        position = (text:find("\n", position, true) or length) + 1
      end
      out[#out + 1] = " "
    elseif long then
      local _, finish = text:find("]" .. long .. "]", position + 2 + #long, true)
      if not finish then return nil end
      position = finish + 1
      out[#out + 1] = " "
    elseif char == '"' or char == "'" then
      local cursor = position + 1
      while true do
        local current = text:sub(cursor, cursor)
        if current == "" or current == "\n" then return nil end
        if current == "\\" then cursor = cursor + 2
        elseif current == char then break
        else cursor = cursor + 1 end
      end
      position = cursor + 1
      out[#out + 1] = " "
    else
      out[#out + 1] = char
      position = position + 1
    end
  end
  return table.concat(out)
end

local FORBIDDEN_WORDS = { "function", "while", "repeat", "for", "goto", "load", "loadstring", "dofile", "require" }

-- A text with its control characters (except line ends and tabs) replaced by a space and a one-line cut at `limit`.
local function one_line(text, limit)
  text = tostring(text):gsub("%c", " "):gsub("^%s+", ""):gsub("%s+$", "")
  if #text > limit then text = text:sub(1, limit) end
  return text
end

local function names_of(dependencies)
  local names, seen = {}, {}
  if type(dependencies) ~= "table" then return names end
  for index = 1, math.min(#dependencies, MAX_DEPENDENCIES) do
    local entry = dependencies[index]
    local name = type(entry) == "string" and entry:match("^%s*([%w_%.%-]+)")
    if name and name ~= "lua" and not seen[name] then
      seen[name] = true
      names[#names + 1] = name
    end
  end
  table.sort(names)
  return names
end

--- Reads the data of a rockspec (the fields `package`, `version`, `description.license`, `description.homepage` and
--- `dependencies`) without running it. A rockspec is Lua, but its content is data: the text is refused when, outside
--- strings and comments, it holds a call (`(`, `:`), a loop, a `goto` or any name that loads code, so that nothing can run
--- or be allocated at will; what remains is evaluated with an empty environment and an instruction limit, the same
--- discipline as `hecate.doc.load_config`.
---@param text string
---@return hecate.doc.Rock? rock  `required_by` is empty and `text` absent
---@return string? problem
function M.parse_rockspec(text)
  if type(text) ~= "string" then return nil, "the rockspec is not text" end
  if #text > MAX_ROCKSPEC_BYTES then return nil, ("the rockspec is larger than %d bytes"):format(MAX_ROCKSPEC_BYTES) end
  local code_only = code_of(text)
  if not code_only then return nil, "the rockspec has an unterminated string or comment" end
  if code_only:find("[():]") then return nil, "the rockspec holds a call, which is not data" end
  for _, word in ipairs(FORBIDDEN_WORDS) do
    if code_only:find("%f[%w_]" .. word .. "%f[^%w_]") then
      return nil, ("the rockspec uses `%s`, which is not data"):format(word)
    end
  end
  local environment = {}
  local chunk, message = load(text, "=rockspec", "t", environment)
  if not chunk then return nil, "the rockspec is not valid Lua: " .. tostring(message):gsub("^[^:]*:%d+: ", "") end
  local thread = coroutine.create(chunk)
  debug.sethook(thread, function() error("instruction limit", 0) end, "", MAX_INSTRUCTIONS)
  local ok, failure = coroutine.resume(thread)
  if not ok then return nil, "the rockspec failed: " .. one_line(failure, 120) end
  local name, version = environment.package, environment.version
  if type(name) ~= "string" or #name > 128 or not name:match(NAME_PATTERN) then
    return nil, "the rockspec has no valid `package` name"
  end
  if type(version) ~= "string" or #version > 128 or not version:match(NAME_PATTERN) then
    return nil, "the rockspec has no valid `version`"
  end
  local description = type(environment.description) == "table" and environment.description or {}
  local license = type(description.license) == "string" and one_line(description.license, MAX_LICENSE_CHARS) or nil
  if license == "" then license = nil end
  local homepage = type(description.homepage) == "string" and one_line(description.homepage, 300) or nil
  return {
    name = name, version = version, license = license, homepage = homepage,
    dependencies = names_of(environment.dependencies), required_by = {},
  }
end

-- A licence text that can be written into a page, or nil and the reason.
local function usable_text(text)
  if #text > MAX_TEXT_BYTES then return nil, ("larger than %d bytes"):format(MAX_TEXT_BYTES) end
  if text:find("\0", 1, true) or not utf8.len(text) then return nil, "not UTF-8 text" end
  text = text:gsub("\r\n?", "\n"):gsub("[\0-\8\11\12\14-\31\127]", " ")
  return text
end

local function is_link(fs, path)
  return fs.is_link ~= nil and fs:is_link(path) == true
end

local function licence_file(name)
  local lower = name:lower()
  return lower:match("^licen[cs]e[%w%._%-]*$") ~= nil or lower:match("^copying[%w%._%-]*$") ~= nil
    or lower:match("^unlicense[%w%._%-]*$") ~= nil
end

-- The licence file of an installed rock: the first file named like one in the directory of the rock, then in its
-- `doc` directory (where LuaRocks installs the `copy_directories` of a rockspec).
local function find_text(fs, directory)
  for _, below in ipairs({ directory, directory .. "/doc" }) do
    for _, entry in ipairs(fs:list(below) or {}) do
      local path = below .. "/" .. entry.name
      if not entry.is_directory and licence_file(entry.name) and not is_link(fs, path) then
        local data = fs:read(path)
        if data then return data, path end
      end
    end
  end
  return nil
end

local function by_name_then_version(a, b)
  if a.name ~= b.name then return a.name < b.name end
  return a.version < b.version
end

---@class hecate.doc.LicensesOptions
---@field tree string  root of the installed tree (a project's `lua_modules`): `<tree>/lib/luarocks/rocks-<lua>/<rock>/<version>/`
---@field roots? string[]  names of the rocks the project depends on: only they and their dependencies, resolved transitively, are listed (default: every installed rock)
---@field max_rocks? integer  default 2000

--- Reads the rocks of an installed tree through `fs` (no process, no `luarocks`): every rock has a rockspec with
--- `description.license` and `dependencies`. Dependencies are resolved by name over every installed version, so the
--- result does not depend on the order of the files. Links are not followed. What cannot be read or resolved is a
--- problem, never an error: the page lists what is known.
---@param fs hecate.doc.FileSystem
---@param options hecate.doc.LicensesOptions
---@return hecate.doc.LicensesModel
function M.read(fs, options)
  local limit = options.max_rocks or MAX_ROCKS
  local problems, found, seen = {}, {}, {}
  local base = options.tree:gsub("/+$", "") .. "/lib/luarocks"
  local kinds = {}
  for _, entry in ipairs(fs:list(base) or {}) do
    if entry.is_directory and entry.name:match("^rocks%-") and not is_link(fs, base .. "/" .. entry.name) then
      kinds[#kinds + 1] = base .. "/" .. entry.name
    end
  end
  if #kinds == 0 then
    problems[#problems + 1] = ("licenses: the tree %s holds no installed rocks (expected %s/rocks-<version>)"):format(options.tree, base)
  end
  local full = false
  for _, rocks_directory in ipairs(kinds) do
    for _, rock_entry in ipairs(fs:list(rocks_directory) or {}) do
      local rock_directory = rocks_directory .. "/" .. rock_entry.name
      if rock_entry.is_directory and not is_link(fs, rock_directory) then
        for _, version_entry in ipairs(fs:list(rock_directory) or {}) do
          local directory = rock_directory .. "/" .. version_entry.name
          local label = rock_entry.name .. " " .. version_entry.name
          if version_entry.is_directory and not is_link(fs, directory) and not seen[label] then
            if #found >= limit then
              if not full then
                full = true
                problems[#problems + 1] = ("licenses: more than %d rocks are installed; only the first %d (by name) are listed")
                  :format(limit, limit)
              end
            else
              seen[label] = true
              local path = ("%s/%s-%s.rockspec"):format(directory, rock_entry.name, version_entry.name)
              local source = not is_link(fs, path) and fs:read(path) or nil
              if source == nil then
                problems[#problems + 1] = ("licenses: rock %s has no readable rockspec at %s"):format(label, path)
              else
                local rock, problem = M.parse_rockspec(source)
                if not rock then
                  problems[#problems + 1] = ("licenses: rock %s: %s (%s)"):format(label, problem, path)
                elseif rock.name ~= rock_entry.name or rock.version ~= version_entry.name then
                  problems[#problems + 1] = ("licenses: rock %s: the rockspec declares %s %s (%s)"):format(
                    label, rock.name, rock.version, path)
                else
                  local data, text_path = find_text(fs, directory)
                  if data then
                    local usable, reason = usable_text(data)
                    if usable then
                      rock.text, rock.text_file = usable, text_path
                    else
                      problems[#problems + 1] = ("licenses: the licence text of rock %s is not reproduced (%s)"):format(label, reason)
                    end
                  end
                  found[#found + 1] = rock
                end
              end
            end
          end
        end
      end
    end
  end
  table.sort(found, by_name_then_version)
  local named = {}
  for _, rock in ipairs(found) do
    named[rock.name] = named[rock.name] or {}
    table.insert(named[rock.name], rock)
  end
  -- The selection: the roots and what they need, or everything. A dependency that is not installed is reported.
  local selected, queue = {}, {}
  local function select_name(name)
    if selected[name] then return end
    selected[name] = true
    queue[#queue + 1] = name
  end
  if options.roots then
    for _, root in ipairs(options.roots) do
      if named[root] then select_name(root)
      else problems[#problems + 1] = ("licenses: the root rock %s is not installed in the tree %s"):format(root, options.tree) end
    end
  else
    for _, rock in ipairs(found) do select_name(rock.name) end
  end
  local index = 1
  local requirers = {}
  while index <= #queue do
    local name = queue[index]
    index = index + 1
    for _, rock in ipairs(named[name]) do
      for _, dependency in ipairs(rock.dependencies) do
        if named[dependency] then
          requirers[dependency] = requirers[dependency] or {}
          requirers[dependency][name] = true
          select_name(dependency)
        else
          problems[#problems + 1] = ("licenses: rock %s %s depends on %s, which is not installed in the tree"):format(
            rock.name, rock.version, dependency)
        end
      end
    end
  end
  local rocks = {}
  for _, rock in ipairs(found) do
    if selected[rock.name] then
      for requirer in pairs(requirers[rock.name] or {}) do rock.required_by[#rock.required_by + 1] = requirer end
      table.sort(rock.required_by)
      rocks[#rocks + 1] = rock
    end
  end
  -- The same missing dependency is reported once per version of the rock that names it: keep the report short.
  local unique, reported = {}, {}
  for _, problem in ipairs(problems) do
    if not reported[problem] then
      reported[problem] = true
      unique[#unique + 1] = problem
    end
  end
  return { rocks = rocks, problems = unique }
end

-- The MIT licence of the Octicons "mark-github" icon (https://github.com/primer/octicons), whose text is the
-- standard one with the copyright line recorded in THIRD_PARTY_NOTICES, section 3.
local OCTICONS_LICENSE = [[
MIT License

Copyright (c) GitHub, Inc.

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
]]

local MERMAID_COMPONENTS = "The bundle holds components under their own licences (VENDORED.md of the theme, checked on "
  .. "2026-11-17): MIT for most of them, ISC (d3), BSD-3-Clause (d3-sankey), Apache-2.0 (chevrotain), "
  .. "MPL-2.0 OR Apache-2.0 (dompurify, used under Apache-2.0) and EPL-2.0 OR GPL-3.0-or-later (elkjs, used under "
  .. "EPL-2.0); the notices stay in the file as comments."

---@class hecate.doc.BundledOptions
---@field diagrams boolean  a page holds a diagram: the site ships Mermaid
---@field theme_fs? hecate.doc.FileSystem  where the files of the theme are read (default: `io`)
---@field theme_directory? string  the `assets` directory of the theme (default: the theme's own)

--- What a generated site bundles or is built with, with the licence texts the theme ships. Mermaid is listed only when a
--- page holds a diagram. The highlight colours of the theme are its own CSS: no colour theme of syntect or two-face is
--- bundled.
---@param options hecate.doc.BundledOptions
---@return hecate.doc.Bundled[]
function M.bundled(options)
  local reader = options.theme_fs or {
    read = function(_, path)
      local file = io.open(path, "rb")
      if not file then return nil end
      local data = file:read("a")
      file:close()
      return data
    end,
  }
  local directory = options.theme_directory or require("hecate.doc.theme").assets_directory()
  local function text_of(path)
    local data = reader:read(directory .. "/" .. path)
    return data and (usable_text(data)) or nil
  end
  local items = {
    { name = "STIX Two Text", use = "body typeface (WOFF2, Latin subset, unmodified)", license = "OFL-1.1", shipped = true,
      text = text_of("fonts/OFL-stix-two-text.txt") },
    { name = "Fira Sans", use = "interface typeface (WOFF2, Latin subset, unmodified)", license = "OFL-1.1", shipped = true,
      text = text_of("fonts/OFL-fira-sans.txt") },
    { name = "Fira Code", use = "monospace typeface (WOFF2, Latin subset, unmodified)", license = "OFL-1.1", shipped = true,
      text = text_of("fonts/OFL-fira-code.txt") },
    { name = "Hecate brand marks", use = "logo, compact mark, favicon, trivium pattern (replaced by the `logo` option)",
      license = "MIT", shipped = true, text = text_of("brand/LICENSE") },
    { name = "Octicons mark-github", use = "icon of the link to the repository", license = "MIT", shipped = true,
      text = OCTICONS_LICENSE },
  }
  if options.diagrams then
    items[#items + 1] = { name = "Mermaid", use = "diagrams (loaded only by the pages that hold one)", license = "MIT",
      shipped = true, text = text_of("mermaid/LICENSE"), note = MERMAID_COMPONENTS }
  end
  items[#items + 1] = { name = "comrak", use = "Markdown rendering (native module)", license = "BSD-2-Clause", shipped = false,
    note = "Also built in: finl_unicode ((MIT OR Apache-2.0) AND Unicode-DFS-2016). The licence texts of the crates are shipped with the release artefacts of the native module (THIRD_PARTY_NOTICES, section 5)." }
  items[#items + 1] = { name = "syntect", use = "syntax highlighting (native module)", license = "MIT", shipped = false }
  items[#items + 1] = { name = "two-face", use = "syntax definitions for syntect (native module)", license = "MIT OR Apache-2.0",
    shipped = false,
    note = "Its embedded syntax definitions are under MIT (48), Apache-2.0 (8), BSD-2-Clause (2) and BSD-3-Clause (1); their notices are shipped with the release artefacts of the native module. No colour theme of syntect or two-face is used: the highlight colours are the own CSS properties of the theme (THIRD_PARTY_NOTICES, section 5)." }
  return items
end

--- Writes the page: after `header` (front matter, generated notice and title, built by the caller), the rocks, the bundled
--- components and the licence texts, each distinct text once with the components it covers.
---@param model hecate.doc.LicensesModel
---@param header string[]  the first lines of the page
---@param bundled? hecate.doc.Bundled[]  default: none
---@return string markdown
function M.markdown(model, header, bundled)
  bundled = bundled or {}
  local lines = {}
  for _, line in ipairs(header) do lines[#lines + 1] = line end
  lines[#lines + 1] = "The third-party software this project uses, with the licence it declares and the licence text where it is"
  lines[#lines + 1] = "available. The rocks are read from the installed tree of the project; a licence is shown as the rockspec of the"
  lines[#lines + 1] = "rock declares it (an SPDX identifier when the rock uses one)."
  lines[#lines + 1] = ""
  lines[#lines + 1] = "## Rocks"
  lines[#lines + 1] = ""
  if #model.rocks == 0 then
    lines[#lines + 1] = "No installed rock was found."
    lines[#lines + 1] = ""
  else
    lines[#lines + 1] = "| Rock | Version | Licence | Required by |"
    lines[#lines + 1] = "|---|---|---|---|"
    for _, rock in ipairs(model.rocks) do
      local required = {}
      for _, name in ipairs(rock.required_by) do required[#required + 1] = code(name, true) end
      lines[#lines + 1] = ("| %s | %s | %s | %s |"):format(code(rock.name, true), plain(rock.version),
        rock.license and code(rock.license, true) or "not declared", table.concat(required, ", "))
    end
    lines[#lines + 1] = ""
  end
  local function component_table(title, shipped)
    local rows = {}
    for _, item in ipairs(bundled) do
      if item.shipped == shipped then rows[#rows + 1] = item end
    end
    if #rows == 0 then return end
    lines[#lines + 1] = title
    lines[#lines + 1] = ""
    lines[#lines + 1] = "| Component | Used for | Licence |"
    lines[#lines + 1] = "|---|---|---|"
    for _, item in ipairs(rows) do
      lines[#lines + 1] = ("| %s | %s | %s |"):format(plain(item.name), plain(item.use), code(item.license, true))
    end
    lines[#lines + 1] = ""
    for _, item in ipairs(rows) do
      if item.note then
        lines[#lines + 1] = ("%s: %s"):format(plain(item.name), plain(item.note))
        lines[#lines + 1] = ""
      end
    end
  end
  if #bundled > 0 then
    lines[#lines + 1] = "## The generated site"
    lines[#lines + 1] = ""
    component_table("### Bundled in the site", true)
    component_table("### Used to build the site, not part of its output", false)
  end
  -- Licence texts, each distinct text once.
  local groups, order = {}, {}
  local without_rocks, without_bundled = {}, {}
  local function add(text, license, label)
    local group = groups[text]
    if not group then
      group = { text = text, licenses = {}, labels = {} }
      groups[text] = group
      order[#order + 1] = group
    end
    group.licenses[license] = true
    group.labels[#group.labels + 1] = label
  end
  for _, rock in ipairs(model.rocks) do
    local label = ("%s %s"):format(code(rock.name), plain(rock.version))
    if rock.text then add(rock.text, rock.license or "not declared", label)
    else without_rocks[#without_rocks + 1] = label end
  end
  for _, item in ipairs(bundled) do
    if item.text then add(item.text, item.license, plain(item.name))
    else without_bundled[#without_bundled + 1] = plain(item.name) end
  end
  lines[#lines + 1] = "## Licence texts"
  lines[#lines + 1] = ""
  if #order == 0 then
    lines[#lines + 1] = "No licence text was found."
    lines[#lines + 1] = ""
  end
  for _, group in ipairs(order) do
    local names = {}
    for name in pairs(group.licenses) do names[#names + 1] = name end
    table.sort(names)
    lines[#lines + 1] = "### " .. plain(table.concat(names, ", "))
    lines[#lines + 1] = ""
    lines[#lines + 1] = "Applies to: " .. table.concat(group.labels, ", ") .. "."
    lines[#lines + 1] = ""
    lines[#lines + 1] = fenced(group.text)
    lines[#lines + 1] = ""
  end
  if #without_rocks > 0 then
    lines[#lines + 1] = "These rocks ship no licence text in the installed tree: " .. table.concat(without_rocks, ", ") .. "."
    lines[#lines + 1] = ""
  end
  if #without_bundled > 0 then
    lines[#lines + 1] = "The licence text is not reproduced here for: " .. table.concat(without_bundled, ", ")
      .. " (see the notes above)."
    lines[#lines + 1] = ""
  end
  return table.concat(lines, "\n")
end

return M
