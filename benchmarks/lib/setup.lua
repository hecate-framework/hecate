-- Module search paths for a network scenario: the sources of the named packages and the native modules built by
-- `build-native`. HECATE_SRC names the checkout whose packages are measured (default: the current directory), so
-- that the A/B comparison runs one set of scenario files against a base and a head tree.
-- Usage, from a scenario run at the repository root: `dofile("benchmarks/lib/setup.lua")({ "core", "reactor" })`.
global <const> _VERSION, package, os, ipairs

---@param names string[]  package directories under packages/
return function(names)
  local src = os.getenv("HECATE_SRC") or "."
  for _, name in ipairs(names) do
    package.path = ("%s/packages/%s/src/?.lua;%s/packages/%s/src/?/init.lua;"):format(src, name, src, name) .. package.path
  end
  local version = _VERSION:match("%d+%.%d+")
  for _, tree in ipairs({ ".hecate/rocks", "spikes/rocks" }) do
    package.cpath = tree .. "/lib/lua/" .. version .. "/?.so;" .. package.cpath
    if src ~= "." then package.cpath = src .. "/" .. tree .. "/lib/lua/" .. version .. "/?.so;" .. package.cpath end
  end
end
