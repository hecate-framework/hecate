-- the whole "CLI": only the Lua standard library
local home = os.getenv("HECATE_HOME")
local tc = home .. "/toolchains/lua-5.5.1"
local cmd = arg[1]
local function sh(c) io.stderr:write("+ ", c, "\n") local ok, how, code = os.execute(c) return ok, code end
if cmd == "install" then
  os.exit(sh(("HECATE_LUAROCKS_CONFIG=1 LUAROCKS_CONFIG=%s/config.lua %s/bin/lua %s/bin/luarocks-relocated --tree lua_modules install dep-a"):format(arg[2], tc, tc)) and 0 or 1)
elseif cmd == "serve" then
  local ok = sh(("%s/bin/lua serve.lua"):format(tc))
  os.exit(ok and 0 or 1)
else
  print("hecate (spike) " .. _VERSION)
end
