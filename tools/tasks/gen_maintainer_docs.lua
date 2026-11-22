-- gen-maintainer-docs: the architecture specifications (`docs/architecture/`) and the ADRs (`docs/adr/`) as pages of
-- the maintainer site (OQ-144, owner decision of 2026-11-21): one page per file under `website/maintainer/en/architecture/`
-- and `website/maintainer/en/adr/`, with the front matter a page needs and the links rewritten
-- (tools/lib/maintainer_docs.lua). The pages are git-ignored, like the code reference: the website workflow runs this task
-- before the site build. The files of `docs/` stay the source of truth; a page that does not carry the marker of this task is
-- never overwritten.
-- Usage: gen-maintainer-docs [--check]   (`--check` writes nothing and fails when a generated page is out of date)
local util = require("lib.util")
local generated_page = require("lib.generated_page")
local maintainer_docs = require("lib.maintainer_docs")

local TASK = "gen-maintainer-docs"
local SECTIONS = {
  { directory = "docs/architecture", title = "Architecture specifications",
    summary = "The specification of each area of hecate. The files under `docs/architecture/` are the source; these pages are generated from them." },
  { directory = "docs/adr", index = false },
}
-- The index of `docs/architecture/` is generated here: a README.md of that directory would be written to the same page.
local SKIPPED = { ["docs/architecture"] = { ["README.md"] = true } }

local function index_page(section, entries)
  local lines = {
    "---",
    ('description: "%s"'):format(section.title .. " of hecate."),
    'hecate: "0.x"',
    'lua: "5.5"',
    "generated: true",
    "---",
    "",
    "# " .. section.title,
    "",
    maintainer_docs.MARKER:format(section.directory .. "/"),
    "",
    section.summary,
    "",
  }
  for _, entry in ipairs(entries) do lines[#lines + 1] = ("- [%s](%s)"):format(entry.title, entry.file) end
  lines[#lines + 1] = ""
  return table.concat(lines, "\n")
end

return {
  description = "generate the maintainer-site pages of docs/architecture and docs/adr (--check to verify only)",
  run = function(ctx)
    local check = false
    for _, a in ipairs(ctx.args) do
      if a == "--check" then check = true else return { ok = false, problems = { "usage: " .. TASK .. " [--check]" } } end
    end
    local problems, counts = {}, { written = 0, unchanged = 0, other = 0 }
    local function apply(relative, content)
      local state, page_problems = generated_page.apply(ctx.root .. "/" .. relative, relative, content,
        { check = check, task = TASK, is_generated = maintainer_docs.is_generated })
      for _, p in ipairs(page_problems) do problems[#problems + 1] = p end
      counts[state] = (counts[state] or 0) + 1
    end
    for _, section in ipairs(SECTIONS) do
      local entries = {}
      for _, name in ipairs(util.list_dir(ctx.root .. "/" .. section.directory)) do
        local skipped = SKIPPED[section.directory] and SKIPPED[section.directory][name]
        if name:find("%.md$") and not skipped and not util.is_dir(ctx.root .. "/" .. section.directory .. "/" .. name) then
          local source = section.directory .. "/" .. name
          local text = (generated_page.read(ctx.root .. "/" .. source) or ""):gsub("\r\n", "\n")
          apply(maintainer_docs.target(source), maintainer_docs.render(source, text))
          entries[#entries + 1] = { file = name, title = (maintainer_docs.describe(text)) }
        end
      end
      if section.index ~= false then
        table.sort(entries, function(a, b) return a.file < b.file end)
        apply(maintainer_docs.OUT_DIR .. "/" .. section.directory:match("[^/]+$") .. "/index.md", index_page(section, entries))
      end
    end
    local total = 0
    for _, n in pairs(counts) do total = total + n end
    return {
      ok = #problems == 0,
      problems = problems,
      output = ("%s: %d pages (%d written, %d unchanged%s)"):format(TASK, total, counts.written, counts.unchanged,
        check and "; check" or ""),
    }
  end,
}
