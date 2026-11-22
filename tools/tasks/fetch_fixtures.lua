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
--
-- Hardening (the entry is data from a file of the repository, the network is not trusted): curl is limited to `https`
-- for the request and for every redirect (without it an https URL can redirect to http and leak the request), a file
-- larger than `max_bytes` (default 16 MiB, `fixtures.MAX_BYTES`, per-entry override `max_bytes`) is refused (without it a
-- hostile endpoint streams gigabytes into memory: the file is read whole and hashed in Lua), a URL that holds `%`, `^`,
-- a quote, a space or a line break is refused (`cmd.exe` expands them on Windows), and the `commit` of a git entry must
-- be 40 or 64 hexadecimal digits and is quoted in the command (an unquoted commit is an injection if pins were ever
-- generated rather than written by hand). An empty download is a failure, and a stale, empty, oversized or
-- mismatching file is deleted. Tests inject `ctx.download`, `ctx.pause` and `ctx.git`.
local util = require("lib.util")
local retry = require("lib.retry")
local fixtures = require("lib.fixtures")

local function git(dir, args)
  return util.capture(("git -C %s %s 2>&1"):format(util.quote(dir), args))
end

local function fetch_git(root, name, entry, problems, run_git, pause)
  local dir = ("%s/.hecate/fixtures/%s/%s"):format(root, name, entry.name)
  if not util.is_dir(dir .. "/.git") then
    util.mkdir(dir)
    local out, ok = run_git(dir, "init -q")
    if not ok then problems[#problems + 1] = entry.name .. ": git init failed: " .. out end
  end
  local latest = os.getenv("HECATE_FIXTURES_LATEST") == "1"
  local head = run_git(dir, "rev-parse HEAD")
  if latest or head ~= entry.commit then
    -- Three tries with a pause: a transient failure of the remote is not a verdict (the checkout is local).
    local fetch = ("fetch -q --depth 1 %s %s"):format(fixtures.word(entry.repository), latest and "HEAD" or fixtures.word(entry.commit))
    local out, ok = retry.run(function() return run_git(dir, fetch) end, 3, 5, pause)
    if ok then out, ok = run_git(dir, "checkout -q -f FETCH_HEAD") end
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
    local directory = ("%s/.hecate/fixtures/%s"):format(ctx.root, name)
    for _, entry in ipairs(chunk()) do
      local kind = fixtures.kind(entry)
      local shape = fixtures.problems(entry)
      for _, problem in ipairs(shape) do problems[#problems + 1] = problem end
      local state, problem
      if #shape > 0 then
        state = "failed"
      elseif kind == "file" then
        state, problem = fixtures.ensure(entry, directory, ctx.download, function(step)
          local out, ok = retry.run(step, 3, 5, ctx.pause)
          return out, ok
        end)
      else
        local before = #problems
        fetch_git(ctx.root, name, entry, problems, ctx.git or git, ctx.pause)
        state = #problems == before and "git" or "failed"
      end
      if problem then problems[#problems + 1] = problem end
      entries[#entries + 1] = { name = tostring(entry.name), kind = kind or "none", state = state or "failed" }
    end
    return { ok = #problems == 0, problems = problems, data = { package = name, entries = entries } }
  end,
}
