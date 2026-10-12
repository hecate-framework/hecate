-- Conventional Commits validation for the commit-msg hook (types mirror pr-hygiene.yml).
local M = {}

M.types = {
  feat = true, fix = true, perf = true, refactor = true, test = true,
  docs = true, build = true, ci = true, chore = true, revert = true,
}

--- Validates the subject line of a commit message.
---@param message string full commit message
---@return string[] problems
function M.check(message)
  local subject
  for line in message:gmatch("[^\r\n]*") do
    if not line:find("^#") and line:find("%S") then subject = line break end
  end
  if not subject then return { "empty commit message" } end
  if subject:find("^Merge ") or subject:find("^Revert \"") or subject:find("^fixup! ")
    or subject:find("^squash! ") then
    return {}
  end
  local ctype, scope, bang, desc = subject:match("^(%a+)(%b())(!?): (.*)$")
  if not ctype then ctype, bang, desc = subject:match("^(%a+)(!?): (.*)$") scope = nil end
  if not ctype then
    return { ("commit subject '%s' does not follow Conventional Commits: type(scope): description"):format(subject) }
  end
  local problems = {}
  if not M.types[ctype] then problems[#problems + 1] = ("unknown commit type '%s'"):format(ctype) end
  if scope == "()" then problems[#problems + 1] = "empty commit scope" end
  if not desc:find("%S") then problems[#problems + 1] = "empty commit description" end
  return problems
end

return M
