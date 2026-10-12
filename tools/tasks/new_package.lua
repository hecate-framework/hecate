-- new-package: scaffolds packages/<name> (README, CLAUDE.md, rockspec, tests/) and its
-- specialist agent, then refreshes the generated catalogue, graph and llms.txt.
-- Usage: new-package <name> --layer "<label>" --phase <n> --summary "<text>" [--deps a,b] [--spec <path>]
-- Layer labels: "0 — Foundation", "1 — Runtime", "2 — Protocol", "3 — Framework", Data, Tooling.
-- Check with the `architect` agent first: a new layer or third-party dependency needs an ADR.
local util = require("lib.util")
local boundaries = require("lib.boundaries")

local function write(path, s)
  local f = assert(io.open(path, "wb"))
  f:write(s)
  f:close()
end

local function parse(args)
  local opts = { deps = {} }
  local i = 1
  while i <= #args do
    local a = args[i]
    if a == "--layer" or a == "--phase" or a == "--summary" or a == "--spec" then
      opts[a:sub(3)] = args[i + 1]
      i = i + 2
    elseif a == "--deps" then
      for d in (args[i + 1] or ""):gmatch("[^,]+") do opts.deps[#opts.deps + 1] = d end
      i = i + 2
    elseif not opts.name and a:sub(1, 2) ~= "--" then
      opts.name = a
      i = i + 1
    else
      return nil, "unexpected argument '" .. a .. "'"
    end
  end
  return opts
end

local function fail(msg) return { ok = false, problems = { msg } } end

return {
  description = 'scaffold a package: new-package <name> --layer "<label>" --phase <n> --summary "<text>" [--deps a,b]',
  run = function(ctx)
    local opts, err = parse(ctx.args)
    if not opts then return fail(err) end
    local name = opts.name
    if not (name and name:match("^[a-z][a-z0-9]*$")) then return fail("package name must match [a-z][a-z0-9]*") end
    if not (opts.layer and boundaries.rank(opts.layer)) then return fail("--layer is required and must be a known layer label") end
    if not (opts.phase and opts.phase:match("^%d+$")) then return fail("--phase <n> is required") end
    if not (opts.summary and opts.summary ~= "") then return fail("--summary is required") end
    local dir = ctx.root .. "/packages/" .. name
    if util.exists(dir) then return fail("packages/" .. name .. " already exists") end
    local rank = boundaries.rank(opts.layer)
    for _, d in ipairs(opts.deps) do
      local readme = io.open(("%s/packages/%s/README.md"):format(ctx.root, d), "rb")
      if not readme then return fail("unknown dependency '" .. d .. "'") end
      local text = readme:read("a")
      readme:close()
      local drank = boundaries.rank(text:match("|%s*Layer%s*|%s*([^|]-)%s*|") or "")
      if drank and drank > rank then return fail(("dependency '%s' is in a higher layer"):format(d)) end
    end
    local deps_cell = #opts.deps == 0 and "none" or (function()
      local cells = {}
      for i, d in ipairs(opts.deps) do cells[i] = ("[`%s`](../%s)"):format(d, d) end
      return table.concat(cells, ", ")
    end)()
    local spec_cell = opts.spec and ("[%s](../../%s)"):format(opts.spec:match("[^/]+$"), opts.spec) or "none yet"
    util.mkdir(dir .. "/tests")
    util.mkdir(ctx.root .. "/.claude/agents")
    write(dir .. "/README.md", ([[
# `hecate-%s`

> %s

| | |
|---|---|
| Module | `hecate.%s` |
| Rock | `hecate-%s` |
| Layer | %s |
| Roadmap phase | %s |
| Status | specified — no code yet |
| Lua | 5.5 (`lua >= 5.5, < 5.6`) |
| Depends on | %s |
| Used by | — |
| Native code | none |
| Specification | %s |
| Decisions | — |
| Agent | [`pkg-%s`](../../.claude/agents/pkg-%s.md) |
| Repository | read-only mirror `hecate-framework/hecate-%s`, generated from this directory (ADR 0017) |

## Responsibilities

-

## Non-goals

-

## Standards and references

-

## Public API

*To be filled during implementation: list every exported class and function with a one-line
description, linking to the generated reference.*

## Layout (once implemented)

```text
src/hecate/%s/init.lua   public entry point
tests/unit/  tests/integration/  tests/fixtures/
examples/    benchmarks/
```
]]):format(name, opts.summary, name, name, opts.layer, opts.phase, deps_cell, spec_cell, name, name, name, name))
    local allowed = #opts.deps == 0 and "none" or ("`hecate." .. table.concat(opts.deps, "`, `hecate.") .. "`")
    write(dir .. "/CLAUDE.md", ([[
# Agent context — `hecate.%s`

You are working inside `packages/%s`. Read the root `CLAUDE.md` first; this file adds
package-specific context. Specialist agent: `pkg-%s`.

## Purpose

%s

## Read before changing anything

- Glossary: `docs/glossary.md` · Coding standards: `docs/architecture/coding-standards.md`
- This package's `README.md` (scope, dependencies, status)

## Boundaries

- Allowed dependencies: %s.
  Anything else requires an ADR; `check-boundaries` fails otherwise.
- If your task needs a change in another package, stop and describe the needed change
  instead of making it (unless the task explicitly spans packages).

## Invariants (must hold after every change)

-

Plus, for every change: unit tests for public behaviour, LuaLS annotations on public API
(`---@async` on anything that may suspend), README "Public API" section updated.
]]):format(name, name, name, opts.summary, allowed))
    write(ctx.root .. "/.claude/agents/pkg-" .. name .. ".md", ([[
---
name: pkg-%s
description: Specialist for the `hecate.%s` package (packages/%s). Use for designing, implementing, reviewing or debugging anything in packages/%s.
tools: Read, Grep, Glob, Edit, Write, Bash
---

You are the maintainer of `hecate.%s`, part of Hecate, a contract-first web API framework
for Lua 5.5.

Scope: %s

Before any work:
1. Read `CLAUDE.md` (root), `packages/%s/CLAUDE.md`, `packages/%s/README.md`.
2. Read `docs/glossary.md`; use its vocabulary in every identifier and sentence.

Working rules:
- Stay inside `packages/%s` unless the task explicitly spans packages.
- Allowed dependencies: %s.
- Tests first for public behaviour; run lint, typecheck and the package tests before
  reporting completion.
- Never invent a decision: missing decisions go to a `Proposed` ADR or
  `docs/open-questions.md`.
]]):format(name, name, name, name, name, opts.summary, name, name, name, allowed))
    for _, task in ipairs({ "gen_rockspecs", "gen_catalogue", "gen_dependency_graph", "gen_llms_txt" }) do
      local report = require("tasks." .. task).run({ root = ctx.root, args = {} })
      if not report.ok then return report end
    end
    return {
      ok = true,
      problems = {},
      output = "created packages/" .. name .. "; still manual: README components table, docs/roadmap.md, Used by rows of the dependencies",
    }
  end,
}
