-- link-modules <project-dir>: fills `<project-dir>/lua_modules` with the Hecate packages of this repository (the Lua
-- sources of every `packages/*/src` merged under `share/lua/5.5/hecate`, and the native modules built into
-- `.hecate/rocks`), so that `hecate test`, `hecate serve`, `hecate contract` and `hecate doc build` run an example
-- or a project of the repository before the rocks are published. Copies (no symbolic link: Windows).
-- Usage: link-modules <project-dir>
local util = require("lib.util")

--- Copies the content of directory `from` into directory `to` (created).
---@param from string
---@param to string
---@return boolean ok
local function copy_tree(from, to)
  util.mkdir(to)
  local cmd
  if util.is_windows() then
    cmd = ('xcopy /E /I /Y /Q %s %s >NUL'):format(util.quote(from), util.quote(to))
  else
    cmd = ("cp -R %s/. %s/"):format(util.quote(from), util.quote(to))
  end
  return os.execute(cmd) == true
end

return {
  description = "copy the Hecate packages of the repository into <project-dir>/lua_modules (to run an example or a project before the rocks exist)",
  run = function(ctx)
    local target = ctx.args[1]
    if not target or target == "" then return { ok = false, problems = { "link-modules: give the project directory" } } end
    target = target:gsub("\\", "/"):gsub("/+$", "")
    local lua = _VERSION:match("%d+%.%d+")
    local share = ("%s/lua_modules/share/lua/%s/hecate"):format(target, lua)
    local problems, packages = {}, 0
    for _, name in ipairs(util.list_dir(ctx.root .. "/packages")) do
      local source = ("%s/packages/%s/src/hecate"):format(ctx.root, name)
      if util.is_dir(source) then
        packages = packages + 1
        if not copy_tree(source, share) then problems[#problems + 1] = "cannot copy " .. source end
      end
    end
    local native = ("%s/.hecate/rocks/lib/lua/%s"):format(ctx.root, lua)
    if util.is_dir(native) then
      if not copy_tree(native, ("%s/lua_modules/lib/lua/%s"):format(target, lua)) then problems[#problems + 1] = "cannot copy " .. native end
    end
    return { ok = #problems == 0, problems = problems, packages = packages, target = target .. "/lua_modules" }
  end,
}
