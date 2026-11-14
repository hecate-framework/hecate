-- usage: lua gen.lua out.c file...   (modules named from path after "src/")
local out = assert(io.open(arg[1], "w"))
out:write('#include <stddef.h>\n')
local names = {}
for i = 2, #arg do
  local path = arg[i]
  local mod = path:match("/src/(.+)%.lua$"):gsub("/", "."):gsub("%.init$", "")
  local f = assert(load(assert(io.open(path, "rb")):read("a"), "@" .. path))
  local bc = string.dump(f, true)
  local id = "m" .. (i - 1)
  local t = {}
  for j = 1, #bc do t[#t + 1] = string.byte(bc, j) end
  out:write(("static const unsigned char %s[] = {%s};\n"):format(id, table.concat(t, ",")))
  names[#names + 1] = ('{"%s", %s, %d}'):format(mod, id, #bc)
end
out:write("struct embedded { const char *name; const unsigned char *data; size_t len; };\n")
out:write("const struct embedded embedded_modules[] = {" .. table.concat(names, ",") .. ",{0,0,0}};\n")
out:close()
