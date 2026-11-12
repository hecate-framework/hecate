-- code-changed [--from <ref> --to <ref>]: prints `true` when the diff between two commits touches anything but
-- documentation (Markdown files, HANDOFF.md, docs/, website/, .claude/, .github/ISSUE_TEMPLATE/), else `false`.
-- Without --from or when the diff cannot be computed (unknown or unreachable commit, force-push) it prints
-- `true`: the tests are never skipped on a doubt. CI skips the platform matrix on `false`.
local util = require("lib.util")
local changes = require("lib.changes")

return {
  description = "false when a diff (--from <ref> --to <ref>, default HEAD) changes only documentation (CI skips the matrix)",
  run = function(ctx)
    local from, to = nil, "HEAD"
    for i, a in ipairs(ctx.args) do
      if a == "--from" then from = ctx.args[i + 1] elseif a == "--to" then to = ctx.args[i + 1] or to end
    end
    local files = {}
    if from and from ~= "" and not from:match("^0+$") then
      local out, ok = util.capture(("git -C %s diff --name-only %s %s"):format(util.quote(ctx.root), util.quote(from), util.quote(to)))
      if ok then
        for f in out:gmatch("[^\r\n]+") do files[#files + 1] = f end
      end
    end
    local answer = changes.code_changed(files)
    return { ok = true, problems = {}, data = answer, output = tostring(answer) }
  end,
}
