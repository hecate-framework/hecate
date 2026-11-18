-- Licence texts of the Rust crates compiled into a native module (gen-rust-licences): the pure part (parsing the
-- output of `cargo tree`, reading an SPDX expression, choosing the licence relied on, grouping identical texts,
-- rendering the page). The task does the I/O. Standard library only.
local M = {}

-- Licences Hecate accepts (deny.toml, plus the permissive licences that only appear as an alternative of an `OR`).
local PERMISSIVE = {
  ["MIT"] = true, ["Apache-2.0"] = true, ["BSD-2-Clause"] = true, ["BSD-3-Clause"] = true, ["ISC"] = true,
  ["Unicode-3.0"] = true, ["Unicode-DFS-2016"] = true, ["Unlicense"] = true, ["Zlib"] = true, ["0BSD"] = true,
}

-- The standard SPDX text, used only for a crate that declares the identifier and ships no licence file. The
-- placeholders of the standard text stay: a copyright holder is never invented.
local FALLBACK = {
  ["MIT"] = [[
MIT License

Copyright (c) <year> <copyright holders>

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated
documentation files (the "Software"), to deal in the Software without restriction, including without limitation the
rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit
persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice (including the next paragraph) shall be included in all copies or
substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE
WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR
COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR
OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
]],
}

--- The standard SPDX text of an identifier, or nil when there is none in this tool.
---@param id string
---@return string?
function M.fallback_text(id) return FALLBACK[id] end

--- Reads the output of `cargo tree --prefix none --format "{p}|{l}"` (one line per crate, repeated crates marked
--- `(*)`). The workspace crate itself (a path crate) is skipped. Sorted by name and version, each crate once.
---@param output string
---@return { name: string, version: string, license: string, proc_macro: boolean }[]? crates, string? problem
function M.parse_tree(output)
  local seen, crates = {}, {}
  for line in (output .. "\n"):gmatch("([^\r\n]*)\r?\n") do
    if line ~= "" then
      local head, license = line:match("^(.-)|(.*)$")
      local name, version, rest = (head or ""):match("^(%S+) v(%S+)(.*)$")
      if not name then return nil, ("cannot read the line of cargo tree: %s"):format(line) end
      if rest:find("%(/") or rest:find("%(%a:[\\/]") then
        -- a path crate: the workspace crate, not a dependency
      else
        local key = name .. " " .. version
        if not seen[key] then
          seen[key] = true
          crates[#crates + 1] = { name = name, version = version, license = (license:gsub("%s*%(%*%)%s*$", "")),
            proc_macro = rest:find("(proc-macro)", 1, true) ~= nil }
        end
      end
    end
  end
  table.sort(crates, function(a, b)
    if a.name ~= b.name then return a.name < b.name end
    return a.version < b.version
  end)
  return crates
end

local function tokens(expression)
  local list = {}
  local text = expression:gsub("/", " OR "):gsub("%(", " ( "):gsub("%)", " ) ")
  for word in text:gmatch("%S+") do list[#list + 1] = word end
  return list
end

--- Reads an SPDX licence expression and returns the identifiers relied on: every term of an `AND`, and for an `OR`
--- the first alternative (in the declared order) made of permissive licences only. The legacy separator `/` of old
--- manifests is an `OR`.
---@param expression string
---@return string[]? ids, string? problem
function M.parse_expression(expression)
  local list = tokens(expression or "")
  if #list == 0 then return nil, "no licence expression" end
  local position = 1
  local rejected = {}
  local parse_or
  local function atom()
    local token = list[position]
    if token == nil then error({ message = "unexpected end of the expression" }) end
    position = position + 1
    if token == "(" then
      local ids = parse_or()
      if list[position] ~= ")" then error({ message = "missing closing parenthesis" }) end
      position = position + 1
      return ids
    end
    if token == ")" or token == "AND" or token == "OR" or token == "WITH" then
      error({ message = ("unexpected '%s'"):format(token) })
    end
    local id = token
    if list[position] == "WITH" then
      if list[position + 1] == nil then error({ message = "unexpected end of the expression" }) end
      id = ("%s WITH %s"):format(token, list[position + 1])
      position = position + 2
    end
    if PERMISSIVE[token] then return { id } end
    rejected[#rejected + 1] = token
    return nil
  end
  local function parse_and()
    local ids = atom()
    while list[position] == "AND" do
      position = position + 1
      local more = atom()
      if ids and more then
        for _, id in ipairs(more) do ids[#ids + 1] = id end
      else
        ids = nil
      end
    end
    return ids
  end
  parse_or = function()
    local chosen = parse_and()
    while list[position] == "OR" do
      position = position + 1
      local alternative = parse_and()
      chosen = chosen or alternative
    end
    return chosen
  end
  local ok, ids = pcall(parse_or)
  if not ok then
    return nil, ("cannot read the licence expression '%s': %s"):format(expression, type(ids) == "table" and ids.message or tostring(ids))
  end
  if position <= #list then return nil, ("cannot read the licence expression '%s': trailing '%s'"):format(expression, list[position]) end
  if not ids then
    return nil, ("no permissive alternative in the licence expression '%s' (not accepted: %s)"):format(expression,
      table.concat(rejected, ", "))
  end
  return ids
end

--- Whether a file name of the root of a crate is a licence file (LICENSE*, LICENCE*, COPYING*, NOTICE*, UNICODE*,
--- COPYRIGHT*), in any case.
---@param name string
---@return boolean
function M.is_licence_file(name)
  local lower = name:lower()
  for _, prefix in ipairs({ "license", "licence", "copying", "notice", "unicode", "copyright" }) do
    if lower:sub(1, #prefix) == prefix then return true end
  end
  return false
end

--- Normalises a text: LF line endings, no trailing blanks on a line, exactly one final newline.
---@param text string
---@return string
function M.normalise(text)
  local lines = {}
  for line in (text:gsub("\r\n", "\n"):gsub("\r", "\n") .. "\n"):gmatch("([^\n]*)\n") do
    lines[#lines + 1] = (line:gsub("[ \t]+$", ""))
  end
  while #lines > 0 and lines[#lines] == "" do lines[#lines] = nil end
  return table.concat(lines, "\n") .. "\n"
end

--- Reads the output of the helper `examples/acknowledgements.rs` of the module `doc`: `LICENCE <type> <path>
--- <bytes>`, then that many bytes of text and a newline, repeated.
---@param output string
---@return { ty: string, path: string, text: string }[]? entries, string? problem
function M.parse_acknowledgements(output)
  local entries, position = {}, 1
  while position <= #output do
    local line_end = output:find("\n", position, true)
    if not line_end then return nil, "the helper output ends inside a header line" end
    local line = output:sub(position, line_end - 1)
    local ty, path, length = line:match("^LICENCE (%S+) (.+) (%d+)$")
    if not ty then return nil, ("unexpected line in the helper output: %s"):format(line) end
    local first = line_end + 1
    local last = first + tonumber(length) - 1
    if last > #output or output:sub(last + 1, last + 1) ~= "\n" then
      return nil, ("the helper output is truncated in the text of %s"):format(path)
    end
    entries[#entries + 1] = { ty = ty, path = (path:gsub("\\", "/")), text = M.normalise(output:sub(first, last)) }
    position = last + 2
  end
  if #entries == 0 then return nil, "the helper printed no licence" end
  return entries
end

--- SHA-256 (through `hex`) of a lock file with LF line endings.
---@param text string
---@param hex fun(s: string): string
---@return string
function M.lock_digest(text, hex) return hex((text:gsub("\r\n", "\n"))) end

--- The digest recorded in the header of a generated page, or nil.
---@param page string
---@return string?
function M.recorded_digest(page) return page:match("Cargo%.lock SHA%-256: `(%x+)`") end

--- The problem of a generated page that does not match the lock file it was generated from (nil when it does):
--- missing, or recorded digest different. Needs no cargo: `check-licenses` runs it, `gen-rust-licences --check` is the
--- complete check.
---@param directory string  the module directory, for the message
---@param lock string?  the text of Cargo.lock
---@param page string?  the text of the page, nil when absent
---@param hex fun(s: string): string
---@return string?
function M.check_page(directory, lock, page, hex)
  if not lock then return nil end
  if not page then
    return ("%s/LICENSES-rust.md is missing: run lua tools/run.lua gen-rust-licences"):format(directory)
  end
  if M.recorded_digest(page) ~= M.lock_digest(lock, hex) then
    return ("%s/LICENSES-rust.md does not match %s/Cargo.lock: run lua tools/run.lua gen-rust-licences"):format(
      directory, directory)
  end
  return nil
end

--- The `authors` of a manifest, as written, or nil.
---@param manifest string
---@return string?
function M.read_authors(manifest)
  local list = manifest:match("\nauthors%s*=%s*%[(.-)%]") or manifest:match("^authors%s*=%s*%[(.-)%]")
  if not list then return nil end
  local names = {}
  for name in list:gmatch('"([^"]*)"') do names[#names + 1] = name end
  if #names == 0 then return nil end
  return table.concat(names, ", ")
end

local function fence_for(text)
  local longest = 0
  for run in text:gmatch("`+") do longest = math.max(longest, #run) end
  return ("`"):rep(math.max(4, longest + 1))
end

local function block(out, text)
  local fence = fence_for(text)
  out[#out + 1] = fence .. "text"
  out[#out + 1] = (text:gsub("\n$", ""))
  out[#out + 1] = fence
  out[#out + 1] = ""
end

local function list_of(items) return table.concat(items, ", ") end

local function unique_sorted(set)
  local list = {}
  for item in pairs(set) do list[#list + 1] = item end
  table.sort(list)
  return list
end

--- Renders the page of a module. `model`: `module`, `directory`, `task`, `lock_sha256`, `crates` (name, version,
--- license, relied, proc_macro, files = { name, text }, fallback = { id, text, authors }), and optionally
--- `syntaxes` = { source, entries = { ty, path, text } }.
---@param model table
---@return string
function M.render(model)
  local crates = {}
  for i, c in ipairs(model.crates) do crates[i] = c end
  table.sort(crates, function(a, b)
    if a.name ~= b.name then return a.name < b.name end
    return a.version < b.version
  end)

  -- Identical texts once, numbered in the order of first appearance.
  local groups, by_text = {}, {}
  local function group_of(text)
    local group = by_text[text]
    if not group then
      group = { number = #groups + 1, text = text, users = {}, user_list = {}, names = {} }
      groups[#groups + 1] = group
      by_text[text] = group
    end
    return group
  end
  local function use(group, c, file_name)
    local label = ("`%s` %s"):format(c.name, c.version)
    if not group.users[label] then
      group.users[label] = true
      group.user_list[#group.user_list + 1] = label
    end
    group.names[file_name] = true
  end
  local rows = {}
  for _, c in ipairs(crates) do
    local numbers, seen, notes = {}, {}, {}
    local files = {}
    for i, f in ipairs(c.files or {}) do files[i] = f end
    table.sort(files, function(a, b) return a.name < b.name end)
    for _, f in ipairs(files) do
      local group = group_of(f.text)
      use(group, c, f.name)
      if not seen[group.number] then
        seen[group.number] = true
        numbers[#numbers + 1] = ("[%d](#licence-text-%d)"):format(group.number, group.number)
      end
    end
    if c.fallback then
      local group = group_of(c.fallback.text)
      use(group, c, "standard text of " .. c.fallback.id)
      numbers[#numbers + 1] = ("[%d](#licence-text-%d)"):format(group.number, group.number)
      notes[#notes + 1] = ("ships no licence file: standard text of %s%s"):format(c.fallback.id,
        c.fallback.authors and (", manifest authors: " .. c.fallback.authors) or "")
    end
    if c.proc_macro then notes[#notes + 1] = "procedural macro, run at compile time and not linked" end
    rows[#rows + 1] = ("| `%s` | %s | %s | %s | %s | %s |"):format(c.name, c.version, c.license,
      table.concat(c.relied or {}, ", "), list_of(numbers), table.concat(notes, "; "))
  end

  local out = {}
  local function add(line) out[#out + 1] = line end
  add(("<!-- generated by `lua tools/run.lua %s`; do not edit. -->"):format(model.task))
  add(("# Licences of the Rust crates of `%s`"):format(model.module))
  add("")
  add(("This file is generated by `lua tools/run.lua %s` from `%s/Cargo.lock` (Cargo.lock SHA-256: `%s`) and is"):format(
    model.task, model.directory, model.lock_sha256))
  add("checked against it by the same task (`--check`). Do not edit it: change the dependencies, then run the task.")
  add("")
  add("It reproduces, for every crate of the normal dependency graph of the module on the platforms Hecate builds for")
  add("(the targets of `deny.toml`: the crates that are compiled into the native module, and the procedural macros that")
  add("build it), the licence files found in the source of the crate (`LICENSE*`, `LICENCE*`, `COPYING*`, `NOTICE*`,")
  add("`UNICODE*`, `COPYRIGHT*`).")
  add("Identical texts are given once. Build-only and development dependencies are not listed.")
  add("")
  add("When a crate offers a choice (`MIT OR Apache-2.0`), Hecate relies on the first permissive alternative in the")
  add("order the crate declares it (column \"Relied on\"); an `AND` requires every term. The texts of the other")
  add("alternatives are reproduced when the crate ships them. A crate that declares an SPDX identifier and ships no")
  add("licence file is given the standard SPDX text of that identifier, marked in the column \"Notes\": the")
  add("placeholders of the standard text (year, copyright holders) are kept as they are.")
  add("")
  add("## Crates")
  add("")
  add("| Crate | Version | Declared licence | Relied on | Texts | Notes |")
  add("|---|---|---|---|---|---|")
  for _, row in ipairs(rows) do add(row) end
  add("")
  add("## Licence texts")
  add("")
  for _, group in ipairs(groups) do
    add(("### Licence text %d"):format(group.number))
    add("")
    add(("Used by: %s."):format(list_of(group.user_list)))
    add("")
    local names = {}
    for name in pairs(group.names) do names[#names + 1] = ("`%s`"):format(name) end
    table.sort(names)
    add(("Source: %s."):format(list_of(names)))
    add("")
    block(out, group.text)
  end

  local syntaxes = model.syntaxes
  if syntaxes then
    local entries = {}
    for i, e in ipairs(syntaxes.entries) do entries[i] = e end
    table.sort(entries, function(a, b)
      if a.path ~= b.path then return a.path < b.path end
      return a.ty < b.ty
    end)
    local texts, order, by = {}, {}, {}
    for _, e in ipairs(entries) do
      local group = by[e.text]
      if not group then
        group = { number = #order + 1, text = e.text, paths = {}, types = {} }
        order[#order + 1] = group
        by[e.text] = group
      end
      group.paths[#group.paths + 1] = e.path
      group.types[e.ty] = true
    end
    texts = order
    add(("## Embedded syntax definitions of %s"):format(syntaxes.source))
    add("")
    add(("The crate embeds syntax definitions (from the `bat` project, themselves from Sublime Text packages) under their own"))
    add(("licences. %d licence files cover them, %d distinct texts; the list below is what `two_face::acknowledgement::listing()`"):format(
      #entries, #texts))
    add("of the locked version returns for the syntaxes (`examples/acknowledgements.rs` prints it). The colour themes of")
    add("the crate are not used and not listed.")
    add("")
    for _, group in ipairs(texts) do
      add(("### Syntax licence text %d"):format(group.number))
      add("")
      add(("Type: %s. Covers %d file(s):"):format(list_of(unique_sorted(group.types)), #group.paths))
      add("")
      for _, path in ipairs(group.paths) do add(("- `%s`"):format(path)) end
      add("")
      block(out, group.text)
    end
  end

  return table.concat(out, "\n"):gsub("\n+$", "") .. "\n"
end

return M
