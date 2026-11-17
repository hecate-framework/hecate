-- Helpers of the `gen-unicode` task (pure functions): reads the Unicode Character Database files `UnicodeData.txt`
-- and `DerivedNormalizationProps.txt` of one pinned version and renders the modules of `hecate.unicode_data`
-- (ADR 0032). Standard library only. Specifications: Unicode Standard 3.11 (Normalization Forms) and UAX #15;
-- UAX #44 for the file formats.
local M = {}

--- The layout version of the generated tables (`format` of `hecate.unicode_data`). A change of layout needs a new
--- ADR and a release of `hecate.unicode` that accepts both layouts first (ADR 0032).
M.FORMAT = 1

--- The permission notice of the Unicode License v3 (SPDX `Unicode-3.0`), https://www.unicode.org/license.txt,
--- which must accompany the data files and their derivatives.
M.LICENSE = [[
UNICODE LICENSE V3

COPYRIGHT AND PERMISSION NOTICE

Copyright © 1991-2026 Unicode, Inc.

NOTICE TO USER: Carefully read the following legal agreement. BY
DOWNLOADING, INSTALLING, COPYING OR OTHERWISE USING DATA FILES, AND/OR
SOFTWARE, YOU UNEQUIVOCALLY ACCEPT, AND AGREE TO BE BOUND BY, ALL OF THE
TERMS AND CONDITIONS OF THIS AGREEMENT. IF YOU DO NOT AGREE, DO NOT
DOWNLOAD, INSTALL, COPY, DISTRIBUTE OR USE THE DATA FILES OR SOFTWARE.

Permission is hereby granted, free of charge, to any person obtaining a
copy of data files and any associated documentation (the "Data Files") or
software and any associated documentation (the "Software") to deal in the
Data Files or Software without restriction, including without limitation
the rights to use, copy, modify, merge, publish, distribute, and/or sell
copies of the Data Files or Software, and to permit persons to whom the
Data Files or Software are furnished to do so, provided that either (a)
this copyright and permission notice appear with all copies of the Data
Files or Software, or (b) this copyright and permission notice appear in
associated Documentation.

THE DATA FILES AND SOFTWARE ARE PROVIDED "AS IS", WITHOUT WARRANTY OF ANY
KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT OF
THIRD PARTY RIGHTS.

IN NO EVENT SHALL THE COPYRIGHT HOLDER OR HOLDERS INCLUDED IN THIS NOTICE
BE LIABLE FOR ANY CLAIM, OR ANY SPECIAL INDIRECT OR CONSEQUENTIAL DAMAGES,
OR ANY DAMAGES WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS,
WHETHER IN AN ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION,
ARISING OUT OF OR IN CONNECTION WITH THE USE OR PERFORMANCE OF THE DATA
FILES OR SOFTWARE.

Except as contained in this notice, the name of a copyright holder shall
not be used in advertising or otherwise to promote the sale, use or other
dealings in these Data Files or Software without prior written
authorization of the copyright holder.
]]

--- The Unicode version of a UCD URL (`https://www.unicode.org/Public/<version>/ucd/<file>`), or nil.
---@param url string
---@return string?
function M.version_of_url(url) return url:match("/Public/(%d+%.%d+%.%d+)/ucd/") end

--- The Unicode version a `https://www.unicode.org/Public/UCD/latest/ReadMe.txt` announces ("... for version 18.0.0 of
--- the Unicode Character Database ..."), or nil.
---@param readme string
---@return string?
function M.latest_version(readme)
  return readme:match("version%s+(%d+%.%d+%.%d+)%s+of%s+the%s+Unicode%s+Character%s+Database")
end

--- Compares two versions `major.minor.update`: -1, 0 or 1.
---@param a string
---@param b string
---@return integer
function M.compare_versions(a, b)
  local function parts(v)
    local major, minor, update = v:match("^(%d+)%.(%d+)%.(%d+)$")
    assert(major, "not a Unicode version: " .. tostring(v))
    return { tonumber(major), tonumber(minor), tonumber(update) }
  end
  local x, y = parts(a), parts(b)
  for i = 1, 3 do
    if x[i] ~= y[i] then return x[i] < y[i] and -1 or 1 end
  end
  return 0
end

local function codepoints(field)
  local list = {}
  for hex in field:gmatch("%x+") do list[#list + 1] = tonumber(hex, 16) end
  return list
end

--- Parses `UnicodeData.txt` (UAX #44, 5.2): the canonical combining class of each code point whose class is not 0
--- and the canonical decomposition mapping of each code point (a compatibility mapping, which starts with `<tag>`,
--- is left out). Returns `{ combining = { [cp] = class }, mappings = { [cp] = { cp... } } }`.
---@param text string
---@return table
function M.parse_unicode_data(text)
  local combining, mappings = {}, {}
  for line in text:gmatch("[^\r\n]+") do
    local fields = {}
    for field in (line .. ";"):gmatch("([^;]*);") do fields[#fields + 1] = field end
    local codepoint = tonumber(fields[1], 16)
    local class = tonumber(fields[4])
    if not (codepoint and class and #fields >= 6) then error("UnicodeData.txt: malformed line: " .. line, 0) end
    if class ~= 0 then combining[codepoint] = class end
    local mapping = fields[6]
    if mapping ~= "" and not mapping:find("^<") then mappings[codepoint] = codepoints(mapping) end
  end
  return { combining = combining, mappings = mappings }
end

--- Parses the property `Full_Composition_Exclusion` of `DerivedNormalizationProps.txt`: the set of the code points
--- that never are the result of a primary composition (the script-specific exclusions, the singletons and the
--- non-starter decompositions; UAX #15, 5.1 and 5.2).
---@param text string
---@return table<integer, true>
function M.parse_exclusions(text)
  local set = {}
  for line in text:gmatch("[^\r\n]+") do
    local first, last = line:match("^(%x+)%.%.(%x+)%s*;%s*Full_Composition_Exclusion%s*#")
    if not first then
      first = line:match("^(%x+)%s*;%s*Full_Composition_Exclusion%s*#")
      last = first
    end
    if first then
      for codepoint = tonumber(first, 16), tonumber(last, 16) do set[codepoint] = true end
    end
  end
  return set
end

--- Builds the tables from the two files. Returns
--- `{ combining = integer[] (flat triples first, last, class, sorted),
---    decomposition = { [cp] = { cp... } } (fully expanded canonical decompositions),
---    composition = { [first] = { [second] = composite } } (the primary composites) }`.
---@param unicode_data string
---@param properties string
---@return table
function M.build(unicode_data, properties)
  local parsed = M.parse_unicode_data(unicode_data)
  local excluded = M.parse_exclusions(properties)
  if next(excluded) == nil then error("DerivedNormalizationProps.txt: no Full_Composition_Exclusion line", 0) end

  local sorted = {}
  for codepoint in pairs(parsed.combining) do sorted[#sorted + 1] = codepoint end
  table.sort(sorted)
  local combining = {}
  local first, last, class
  for _, codepoint in ipairs(sorted) do
    if first and codepoint == last + 1 and parsed.combining[codepoint] == class then
      last = codepoint
    else
      if first then table.move({ first, last, class }, 1, 3, #combining + 1, combining) end
      first, last, class = codepoint, codepoint, parsed.combining[codepoint]
    end
  end
  if first then table.move({ first, last, class }, 1, 3, #combining + 1, combining) end

  local expanded = {}
  local function expand(codepoint, depth)
    if expanded[codepoint] then return expanded[codepoint] end
    if depth > 8 then error(("decomposition of U+%04X does not end"):format(codepoint), 0) end
    local out = {}
    for _, part in ipairs(parsed.mappings[codepoint]) do
      if parsed.mappings[part] then
        for _, inner in ipairs(expand(part, depth + 1)) do out[#out + 1] = inner end
      else
        out[#out + 1] = part
      end
    end
    expanded[codepoint] = out
    return out
  end
  local decomposition, composition = {}, {}
  for codepoint, mapping in pairs(parsed.mappings) do
    decomposition[codepoint] = expand(codepoint, 1)
    if #mapping == 2 and not excluded[codepoint] then
      local row = composition[mapping[1]] or {}
      composition[mapping[1]] = row
      row[mapping[2]] = codepoint
    end
  end
  return { combining = combining, decomposition = decomposition, composition = composition }
end

local function sorted_keys(map)
  local keys = {}
  for key in pairs(map) do keys[#keys + 1] = key end
  table.sort(keys)
  return keys
end

local function header(meta, what)
  local lines = { "-- GENERATED by `lua tools/run.lua gen-unicode`: do not edit by hand.", "--" }
  lines[#lines + 1] = ("-- %s"):format(what)
  lines[#lines + 1] = ("-- Source: Unicode Character Database %s, %s (https://www.unicode.org/Public/%s/ucd/)."):format(
    meta.version, table.concat(meta.files, " and "), meta.version)
  lines[#lines + 1] = ("-- Layout `format` %d."):format(M.FORMAT)
  lines[#lines + 1] = "--"
  for line in M.LICENSE:gmatch("([^\n]*)\n") do lines[#lines + 1] = line == "" and "--" or ("-- " .. line) end
  lines[#lines + 1] = ""
  return table.concat(lines, "\n")
end

local function hex(codepoint) return ("0x%04X"):format(codepoint) end

--- Renders the modules: `{ ["init.lua"] = text, ["combining_class.lua"] = text, ... }`. `meta` is
--- `{ version = "18.0.0", files = { "UnicodeData.txt", ... } }`.
---@param model table  from `build`
---@param meta table
---@return table<string, string>
function M.render(model, meta)
  local files = {}

  local out = { header(meta, "Canonical combining classes: flat triples `first, last, class` of the code points whose class is not 0, in ascending order."), "global none", "", "return {" }
  for i = 1, #model.combining, 3 do
    out[#out + 1] = ("  %s, %s, %d,"):format(hex(model.combining[i]), hex(model.combining[i + 1]), model.combining[i + 2])
  end
  out[#out + 1] = "}\n"
  files["combining_class.lua"] = table.concat(out, "\n")

  out = { header(meta, "Fully expanded canonical decompositions: `[code point] = { code point... }`. Hangul syllables are not listed (algorithmic)."), "global none", "", "return {" }
  for _, codepoint in ipairs(sorted_keys(model.decomposition)) do
    local parts = {}
    for i, part in ipairs(model.decomposition[codepoint]) do parts[i] = hex(part) end
    out[#out + 1] = ("  [%s] = { %s },"):format(hex(codepoint), table.concat(parts, ", "))
  end
  out[#out + 1] = "}\n"
  files["decomposition.lua"] = table.concat(out, "\n")

  out = { header(meta, "Primary composites: `[first] = { [second] = composite }`, without the Full_Composition_Exclusion code points. Hangul syllables are not listed (algorithmic)."), "global none", "", "return {" }
  for _, first in ipairs(sorted_keys(model.composition)) do
    local pairs_list = {}
    for _, second in ipairs(sorted_keys(model.composition[first])) do
      pairs_list[#pairs_list + 1] = ("[%s] = %s"):format(hex(second), hex(model.composition[first][second]))
    end
    out[#out + 1] = ("  [%s] = { %s },"):format(hex(first), table.concat(pairs_list, ", "))
  end
  out[#out + 1] = "}\n"
  files["composition.lua"] = table.concat(out, "\n")

  out = { header(meta, "Loader of the tables of `hecate-unicode-data`: the Unicode version, the layout `format` and the lazy loading of each table."),
    "global <const> require, type, error, tostring",
    "",
    "local TABLES = { combining_class = true, decomposition = true, composition = true }",
    "",
    "--- The tables of the Unicode Character Database: `unicode_version`, `format` and `load`.",
    "---@class hecate.unicode_data",
    "---@field unicode_version string  the Unicode version of the tables, for example \"18.0.0\"",
    "---@field format integer  the layout of the tables; `hecate.unicode` refuses a layout it does not know",
    "local M = {",
    ("  unicode_version = %q,"):format(meta.version),
    ("  format = %d,"):format(M.FORMAT),
    "}",
    "",
    "--- Returns one table (`combining_class`, `decomposition` or `composition`), loaded on first use.",
    "---@param name string",
    "---@return table",
    "function M.load(name)",
    "  if type(name) ~= \"string\" or not TABLES[name] then error(\"unknown Unicode data table: \" .. tostring(name), 2) end",
    "  return (require(\"hecate.unicode_data.\" .. name))",
    "end",
    "",
    "return M",
    "" }
  files["init.lua"] = table.concat(out, "\n")
  return files
end

return M
