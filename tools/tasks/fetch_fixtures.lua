-- fetch-fixtures [package]: downloads the third-party test data a package declares in
-- `packages/<package>/tests/external.lua` (default: json) into `.hecate/fixtures/<package>/<name>`,
-- which is git-ignored. Each entry is { name, repository, commit, path }: the data is fetched with git at that
-- exact commit (the commit hash pins the content) and the suite reads `<name>/<path>`. Without network access
-- the task fails and the suites that need the data skip locally (they fail in CI).
-- With HECATE_FIXTURES_LATEST=1 it fetches the head of the default branch instead of the pinned commit
-- (for scheduled runs that watch for new cases; a pull request must stay on the pin).
local util = require("lib.util")

-- `util.quote` turns "/" into "\\" on Windows (it quotes paths); a URL must keep its slashes.
local function quote_url(url)
  if util.is_windows() then return '"' .. url:gsub('"', '""') .. '"' end
  return "'" .. url:gsub("'", "'\\''") .. "'"
end

local function git(dir, args)
  return util.capture(("git -C %s %s 2>&1"):format(util.quote(dir), args))
end

return {
  description = "download the third-party test data of a package (default: json) at the pinned commits",
  run = function(ctx)
    local name = ctx.args[1] or "json"
    local spec = ("%s/packages/%s/tests/external.lua"):format(ctx.root, name)
    local chunk = loadfile(spec)
    if not chunk then return { ok = true, problems = {} } end
    local problems = {}
    for _, entry in ipairs(chunk()) do
      local dir = ("%s/.hecate/fixtures/%s/%s"):format(ctx.root, name, entry.name)
      if not util.is_dir(dir .. "/.git") then
        util.mkdir(dir)
        local out, ok = git(dir, "init -q")
        if not ok then problems[#problems + 1] = entry.name .. ": git init failed: " .. out end
      end
      local latest = os.getenv("HECATE_FIXTURES_LATEST") == "1"
      local head = git(dir, "rev-parse HEAD")
      if latest or head ~= entry.commit then
        local out, ok = git(dir, ("fetch -q --depth 1 %s %s"):format(quote_url(entry.repository), latest and "HEAD" or entry.commit))
        if ok then out, ok = git(dir, "checkout -q -f FETCH_HEAD") end
        if not ok then problems[#problems + 1] = ("%s: cannot fetch %s at %s: %s"):format(entry.name, entry.repository, entry.commit, out) end
      end
    end
    return { ok = #problems == 0, problems = problems }
  end,
}
