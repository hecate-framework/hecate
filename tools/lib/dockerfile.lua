-- Helpers of the `check-docker` task (pure functions): the static rules that every image of `docker/` obeys
-- (docker/README.md, "Requirements"): a pinned base image, system CA certificates (ADR 0024), a non-root user and the
-- OCI labels. They read the text of a Dockerfile, so they run without a Docker daemon.
local M = {}

--- The stages of a Dockerfile: `{ { from = "debian:${TAG}", lines = { "RUN ...", ... } }, ... }`, in order. Comments are
--- dropped and a line ending in a backslash is joined with the next one. Lines before the first `FROM` (the `ARG`s) are
--- returned as the stage `preamble`.
---@param text string
---@return { preamble: string[], stages: { from: string, lines: string[] }[] }
function M.parse(text)
  local joined, current = {}, ""
  for line in (text .. "\n"):gmatch("(.-)\r?\n") do
    local stripped = line:match("^%s*(.-)%s*$")
    if stripped:sub(1, 1) ~= "#" then
      if stripped:sub(-1) == "\\" then
        current = current .. stripped:sub(1, -2) .. " "
      else
        current = current .. stripped
        if current ~= "" then joined[#joined + 1] = current end
        current = ""
      end
    end
  end
  if current ~= "" then joined[#joined + 1] = current end
  local result = { preamble = {}, stages = {} }
  for _, line in ipairs(joined) do
    local from = line:match("^FROM%s+(%S+)")
    if from then
      result.stages[#result.stages + 1] = { from = from, lines = {} }
    elseif #result.stages == 0 then
      result.preamble[#result.preamble + 1] = line
    else
      local stage = result.stages[#result.stages]
      stage.lines[#stage.lines + 1] = line
    end
  end
  return result
end

-- The default of each `ARG name=value` of the preamble.
local function defaults(preamble)
  local map = {}
  for _, line in ipairs(preamble) do
    local name, value = line:match("^ARG%s+([%w_]+)=(%S+)")
    if name then map[name] = value end
  end
  return map
end

--- The problems of one Dockerfile (`label` names it in the messages). An empty list means it complies.
---@param label string
---@param text string
---@return string[]
function M.check(label, text)
  local problems = {}
  local parsed = M.parse(text)
  local args = defaults(parsed.preamble)
  if #parsed.stages == 0 then return { label .. ": no FROM instruction" } end
  for _, stage in ipairs(parsed.stages) do
    local image = (stage.from:gsub("%${([%w_]+)}", function(name) return args[name] or ("${" .. name .. "}") end))
    if image:find("%${") then
      problems[#problems + 1] = ("%s: the base image %s uses a variable without a default"):format(label, stage.from)
    elseif not image:find("@sha256:", 1, true) then
      local tag = image:match("^[^/:]+[^:]*:([^:]+)$") or image:match("^[^:]+:([^:]+)$")
      if not tag or tag == "latest" then
        problems[#problems + 1] = ("%s: the base image %s is not pinned by a tag or a digest"):format(label, image)
      end
    end
  end
  local final = parsed.stages[#parsed.stages]
  local user, labelled, ca = nil, false, false
  for _, line in ipairs(final.lines) do
    local u = line:match("^USER%s+(%S+)")
    if u then user = u end
    if line:find("org.hecate.lua-version=", 1, true) then labelled = true end
    if line:find("ca-certificates", 1, true) then ca = true end
  end
  if not user or user == "root" or user:match("^0") then
    problems[#problems + 1] = label .. ": the final stage must end as a non-root user (USER instruction)"
  end
  if not labelled then problems[#problems + 1] = label .. ": the final stage lacks the label org.hecate.lua-version" end
  if not ca then problems[#problems + 1] = label .. ": the final stage does not install ca-certificates (ADR 0024)" end
  return problems
end

--- The Dockerfile paths a `bake.hcl` names (`dockerfile = "docker/x/Dockerfile.${variant}"`), expanded with the
--- variants of its `matrix`.
---@param text string
---@return string[]
function M.bake_dockerfiles(text)
  local paths = {}
  for block in text:gmatch("target%s+\"[%w_-]+\"%s*(%b{})") do
    local template = block:match('dockerfile%s*=%s*"([^"]+)"')
    if template then
      local variants = block:match("matrix%s*=%s*{%s*variant%s*=%s*%[(.-)%]")
      if variants and template:find("${variant}", 1, true) then
        for v in variants:gmatch('"([^"]+)"') do paths[#paths + 1] = (template:gsub("%${variant}", v)) end
      else
        paths[#paths + 1] = template
      end
    end
  end
  return paths
end

return M
