-- fetch-fixtures [package]: downloads the third-party test data a package declares in
-- `packages/<package>/tests/external.lua` (default: json) into `.hecate/fixtures/<package>/<name>`,
-- which is git-ignored. An entry is one of two kinds. { name, repository, commit, path }: the data is fetched with
-- git at that exact commit (the commit hash pins the content) and the suite reads `<name>/<path>`.
-- { name, url, sha256 }: one file downloaded from an https URL into `<name>` and verified against its SHA-256
-- (published by version, as the Unicode Character Database is); a file that does not match is deleted and reported
-- (ADR 0032). The report of `--json` lists each entry with its kind and state. Without network access
-- the task fails (after three tries of each fetch, 5 s apart) and the suites that need the data skip locally (they fail in CI).
-- With HECATE_FIXTURES_LATEST=1 it fetches the head of the default branch instead of the pinned commit
-- (for scheduled runs that watch for new cases; a pull request must stay on the pin).
local util = require("lib.util")
local retry = require("lib.retry")
local fixtures = require("lib.fixtures")

-- `util.quote` turns "/" into "\\" on Windows (it quotes paths); a URL must keep its slashes.
local function quote_url(url)
  if util.is_windows() then return '"' .. url:gsub('"', '""') .. '"' end
  return "'" .. url:gsub("'", "'\\''") .. "'"
end

local function git(dir, args)
  return util.capture(("git -C %s %s 2>&1"):format(util.quote(dir), args))
end

local function fetch_git(root, name, entry, problems)
  local dir = ("%s/.hecate/fixtures/%s/%s"):format(root, name, entry.name)
  if not util.is_dir(dir .. "/.git") then
    util.mkdir(dir)
    local out, ok = git(dir, "init -q")
    if not ok then problems[#problems + 1] = entry.name .. ": git init failed: " .. out end
  end
  local latest = os.getenv("HECATE_FIXTURES_LATEST") == "1"
  local head = git(dir, "rev-parse HEAD")
  if latest or head ~= entry.commit then
    -- Three tries with a pause: a transient failure of the remote is not a verdict (the checkout is local).
    local fetch = ("fetch -q --depth 1 %s %s"):format(quote_url(entry.repository), latest and "HEAD" or entry.commit)
    local out, ok = retry.run(function() return git(dir, fetch) end, 3, 5)
    if ok then out, ok = git(dir, "checkout -q -f FETCH_HEAD") end
    if not ok then problems[#problems + 1] = ("%s: cannot fetch %s at %s: %s"):format(entry.name, entry.repository, entry.commit, out) end
  end
end

return {
  description = "download the third-party test data of a package (default: json) at the pinned commits or checksums",
  run = function(ctx)
    local name = ctx.args[1] or "json"
    local spec = ("%s/packages/%s/tests/external.lua"):format(ctx.root, name)
    local chunk = loadfile(spec)
    if not chunk then return { ok = true, problems = {} } end
    local problems, entries = {}, {}
    for _, entry in ipairs(chunk()) do
      local kind = fixtures.kind(entry)
      if not kind then
        problems[#problems + 1] = tostring(entry.name) .. ": an entry needs repository and commit, or url and sha256"
      elseif kind == "file" then
        local shape = fixtures.problems(entry)
        for _, problem in ipairs(shape) do problems[#problems + 1] = problem end
        local state, problem
        if #shape == 0 then
          state, problem = fixtures.ensure(entry, ("%s/.hecate/fixtures/%s"):format(ctx.root, name), nil, function(step)
            local out, ok = retry.run(step, 3, 5)
            return out, ok
          end)
        end
        if problem then problems[#problems + 1] = problem end
        entries[#entries + 1] = { name = entry.name, kind = kind, state = state or "failed" }
      else
        fetch_git(ctx.root, name, entry, problems)
        entries[#entries + 1] = { name = entry.name, kind = kind, state = "git" }
      end
    end
    return { ok = #problems == 0, problems = problems, data = { package = name, entries = entries } }
  end,
}
