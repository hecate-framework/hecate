-- The specialist agent of a package (`.claude/agents/pkg-<name>.md`): one template, used by `new-package` to
-- scaffold it and checked against every existing agent by tools/tests/agent_test.lua (pure functions).
local M = {}

--- First words that are product names and keep their capital letter in the description.
local PROPER = { Redis = true, Microsoft = true }

--- The scope of a package turned into the object of "questions about ...": the first letter is lower-cased,
--- unless the first word is a name (it has a capital letter or a digit after its first character, or it is in `PROPER`:
--- `HTTP/1.1 server`, `MySQL and MariaDB driver`, `Redis client`).
---@param scope string
---@return string
function M.about(scope)
  local word = scope:match("^[%w%-/%.]+") or ""
  if PROPER[word] or word:sub(2):find("[%u%d]") then return scope end
  return (scope:gsub("^%u", string.lower))
end

--- The "Allowed dependencies" text for a list of package names (without the `hecate.` prefix).
---@param deps string[]
---@return string
function M.allowed(deps)
  if #deps == 0 then return "Lua standard library only." end
  local names = {}
  for i, d in ipairs(deps) do names[i] = "`hecate." .. d .. "`" end
  return table.concat(names, ", ") .. "."
end

---@class hecate.tools.AgentSpec
---@field name string  package name ("sql")
---@field module? string  module name written in the text (default `hecate.<name>`; `hecate` for the meta-package)
---@field scope string  the summary line of the README
---@field doc string  document that specifies the package, for example `docs/architecture/data-access.md`
---@field allowed string  the "Allowed dependencies" text (see `allowed`)
---@field standards? string  default "—"
---@field about? string  default `about(scope)`

--- Renders the agent file of a package.
---@param spec hecate.tools.AgentSpec
---@return string
function M.render(spec)
  local name = spec.name
  local module = spec.module or ("hecate." .. name)
  local lines = {
    "---",
    "name: pkg-" .. name,
    ("description: Specialist for the `%s` package (packages/%s). Use for designing, implementing, reviewing or debugging anything in packages/%s, and for questions about %s."):format(
      module, name, name, spec.about or M.about(spec.scope):gsub("%.$", "")),
    "tools: Read, Grep, Glob, Edit, Write, Bash",
    "---",
    "",
    ("You are the maintainer of `%s`, part of Hecate, a contract-first web API framework"):format(module),
    "for Lua 5.5.",
    "",
    "Scope: " .. spec.scope,
    "",
    "Before any work:",
    ("1. Read `CLAUDE.md` (root), `packages/%s/CLAUDE.md`, `packages/%s/README.md`."):format(name, name),
    ("2. Read `%s` and the ADRs listed in the package README."):format(spec.doc),
    "3. Read `docs/glossary.md`; use its vocabulary in every identifier and sentence.",
    "",
    "Working rules:",
    ("- Stay inside `packages/%s` unless the task explicitly spans packages; report needed"):format(name),
    "  changes elsewhere instead of making them.",
    "- Allowed dependencies: " .. spec.allowed,
    ("- Preserve the invariants listed in `packages/%s/CLAUDE.md`; add a test for each one"):format(name),
    "  you touch.",
    "- Relevant standards: " .. (spec.standards or "—") .. ". Cite section numbers in code",
    "  comments when implementing normative behaviour.",
    "- Tests first for public behaviour; run format, lint, typecheck and the package tests",
    "  before reporting completion.",
    "- Never invent a decision: missing decisions go to a `Proposed` ADR or",
    "  `docs/open-questions.md`.",
    "",
    "When reviewing, report findings ordered by severity with file and line references, and",
    "state explicitly which invariants you verified.",
  }
  return table.concat(lines, "\n") .. "\n"
end

return M
