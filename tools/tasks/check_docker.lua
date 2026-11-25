-- check-docker: the static rules of the images of `docker/` (docker/README.md, "Requirements"), checked without a Docker
-- daemon: every `docker/<image>/Dockerfile.<variant>` pins its base images by tag or digest, installs the system CA
-- certificates (ADR 0024), ends as a non-root user and carries the label `org.hecate.lua-version`; and every
-- Dockerfile that `docker/bake.hcl` names exists, and every Dockerfile is named by it. The build itself and the Trivy
-- scan belong to `docker.yml`.
local util = require("lib.util")
local dockerfile = require("lib.dockerfile")

local function read(path)
  local f = io.open(path, "rb")
  if not f then return nil end
  local d = f:read("a")
  f:close()
  return d
end

return {
  description = "the Dockerfiles pin their base images, install CA certificates, run as non-root and carry the Lua label",
  run = function(ctx)
    local problems, files = {}, {}
    for _, image in ipairs(util.list_dir(ctx.root .. "/docker")) do
      if util.is_dir(ctx.root .. "/docker/" .. image) then
        for _, name in ipairs(util.list_dir(ctx.root .. "/docker/" .. image)) do
          if name:match("^Dockerfile%.%w+$") then files[#files + 1] = ("docker/%s/%s"):format(image, name) end
        end
      end
    end
    table.sort(files)
    local present = {}
    for _, relative in ipairs(files) do
      present[relative] = true
      for _, problem in ipairs(dockerfile.check(relative, read(ctx.root .. "/" .. relative) or "")) do
        problems[#problems + 1] = problem
      end
    end
    local bake = read(ctx.root .. "/docker/bake.hcl")
    if not bake then
      problems[#problems + 1] = "docker/bake.hcl is missing"
    else
      local named = {}
      for _, path in ipairs(dockerfile.bake_dockerfiles(bake)) do
        named[path] = true
        if not present[path] then problems[#problems + 1] = ("docker/bake.hcl names %s, which does not exist"):format(path) end
      end
      for _, relative in ipairs(files) do
        if not named[relative] then problems[#problems + 1] = ("%s is not built by docker/bake.hcl"):format(relative) end
      end
    end
    return { ok = #problems == 0, problems = problems, data = files }
  end,
}
