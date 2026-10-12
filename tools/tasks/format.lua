-- format / format-check: the repository has no formatter until one fully supports
-- Lua 5.5 (OQ-3, owner decision 2026-10-12). Both tasks succeed and say so.
return {
  description = "no formatter configured for the repository (OQ-3); always succeeds",
  run = function()
    return { ok = true, problems = {} }
  end,
}
