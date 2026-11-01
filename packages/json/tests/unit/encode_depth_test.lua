-- The depth ceiling of the encoder (1000 levels, native/src/lib.rs DEPTH_CEILING): the walk recurses on the native
-- stack, so a value at the ceiling must be encoded, compact or pretty, on the stack of the smallest main thread
-- (1 MiB on Windows, where this file runs in CI), and one level beyond must be a `depth_limit` error, not a crash.
local test = require("harness.test")
local core = require("hecate.core")
local json = require("hecate.json")
local T = test.Case("JsonEncodeDepthTest")

local CEILING = 1000

local function nested_arrays(depth)
  local value = json.array()
  for _ = 2, depth do value = json.array({ value }) end
  return value
end

local function nested_objects(depth)
  local value = json.object()
  for _ = 2, depth do value = json.object({ k = value }) end
  return value
end

local FORMS = {
  { name = "compact", options = {} },
  { name = "indent", options = { indent = 2, max_size = 16 * 1024 * 1024 } },
  { name = "pretty", options = { pretty = true, max_size = 16 * 1024 * 1024 } },
  { name = "canonical", options = { canonical = true } },
}

function T:test_arrays_at_the_ceiling_are_encoded_in_every_form()
  local value = nested_arrays(CEILING)
  for _, form in ipairs(FORMS) do
    local text = json.encode(value, form.options)
    self:assert_equal("string", type(text), form.name)
    self:assert_true(#text >= 2 * CEILING, form.name)
    self:assert_equal(CEILING, select(2, text:gsub("%[", "")), form.name)
  end
  self:assert_equal(("["):rep(CEILING) .. ("]"):rep(CEILING), json.encode(value))
end

function T:test_objects_at_the_ceiling_are_encoded_in_every_form()
  local value = nested_objects(CEILING)
  for _, form in ipairs(FORMS) do
    local text = json.encode(value, form.options)
    self:assert_equal("string", type(text), form.name)
    self:assert_equal(CEILING, select(2, text:gsub("{", "")), form.name)
  end
  self:assert_equal(('{"k":'):rep(CEILING - 1) .. "{}" .. ("}"):rep(CEILING - 1), json.encode(value))
end

function T:test_one_level_beyond_the_ceiling_is_a_depth_limit_error_in_every_form()
  for _, value in ipairs({ nested_arrays(CEILING + 1), nested_objects(CEILING + 1) }) do
    for _, form in ipairs(FORMS) do
      local err = self:assert_error(function() return json.encode(value, form.options) end)
      self:assert_true(core.is_instance_of(err, json.EncodeError), tostring(err))
      self:assert_equal("depth_limit", err.context.reason, form.name)
    end
  end
end

function T:test_the_ceiling_is_encoded_on_a_one_mebibyte_stack()
  -- A child process with `ulimit -s 1024` (POSIX shells only). A stack overflow is a SIGSEGV, not a Lua error: the
  -- child prints "start" before and "done" after, so a crash shows as "start" without "done".
  if package.config:sub(1, 1) ~= "/" or arg == nil or arg[-1] == nil then return end
  -- A preloaded sanitizer runtime has its own needs for the stack and the address space: nothing is proved with it.
  if os.getenv("LD_PRELOAD") or os.getenv("DYLD_INSERT_LIBRARIES") then return end
  local script = os.tmpname()
  local file = assert(io.open(script, "w"))
  file:write([[
local json = require("hecate.json")
local function nest(depth, make)
  local value = make()
  for _ = 2, depth do value = make(value) end
  return value
end
local arrays = nest(1000, function(inner) return json.array({ inner }) end)
local objects = nest(1000, function(inner) return json.object({ k = inner }) end)
io.write("start\n") io.flush()
for _, value in ipairs({ arrays, objects }) do
  for _, options in ipairs({ {}, { indent = 2, max_size = 16 * 1024 * 1024 }, { canonical = true } }) do
    assert(#json.encode(value, options) >= 2000)
  end
end
io.write("done\n")
]])
  file:close()
  local function quote(text) return "'" .. text:gsub("'", "'\\''") .. "'" end
  local command = ("ulimit -s 1024 && LUA_PATH=%s LUA_CPATH=%s %s %s 2>&1"):format(
    quote(package.path), quote(package.cpath), quote(arg[-1]), quote(script))
  local pipe = io.popen(command)
  local output = pipe and pipe:read("a") or ""
  if pipe then pipe:close() end
  os.remove(script)
  -- A shell that refuses the limit reports it itself and `&&` skips the interpreter; an empty output means the same:
  -- the stack could not be capped, nothing was provoked.
  if output:find("ulimit", 1, true) or output:find("^%s*$") then return end
  self:assert_true(output:find("done", 1, true) ~= nil, "the encoder did not finish on a 1 MiB stack: " .. output)
end

return T
