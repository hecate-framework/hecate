-- Classification of changed files for CI: does a push change anything that the tests or the code checks can
-- see? Pure Markdown and documentation changes do not (their own checks are `docs.yml` and the light
-- `docs-checks` job of `ci.yml`). Standard library only.
local M = {}

-- Directory prefixes whose content never reaches the tests or the code checks.
local DOC_PREFIXES = { "docs/", "website/", ".claude/", ".github/ISSUE_TEMPLATE/" }

--- True when a changed file cannot change the result of the code checks and the tests.
---@param path string
---@return boolean
function M.is_documentation(path)
  path = path:gsub("\\", "/")
  if path:sub(-3):lower() == ".md" or path == "HANDOFF.md" then return true end
  for _, prefix in ipairs(DOC_PREFIXES) do
    if path:sub(1, #prefix) == prefix then return true end
  end
  return false
end

--- True when at least one of the files is not documentation. An empty list is a code change (a diff that
--- could not be computed must not skip the tests).
---@param files string[]
---@return boolean
function M.code_changed(files)
  if #files == 0 then return true end
  for _, path in ipairs(files) do
    if not M.is_documentation(path) then return true end
  end
  return false
end

return M
