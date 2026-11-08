-- Report violations to a client: `check` raises a `ValidationError`, and its violations become the plain
-- table of a problem details response (the kernel does this conversion for you).
local core = require("hecate.core")
local schema = require("hecate.schema")

local user = schema.object({
  name = schema.string({ min_length = 1 }),
  age = schema.integer({ minimum = 0 }),
})

local ok, err = pcall(user.check, user, { name = "", age = -1 })
print(ok, core.is_instance_of(err, core.ValidationError))

-- One entry per violation: the JSON Pointer of the value, the stable code and the message (no client value in it).
local problem = { type = "about:blank", title = "The content is not valid", status = 400, errors = {} }
for _, violation in ipairs(err.context.violations) do
  problem.errors[#problem.errors + 1] = { pointer = violation.path, code = violation.code, detail = violation.message }
end
for _, entry in ipairs(problem.errors) do
  print(entry.pointer, entry.code, entry.detail)
end

-- A conforming value is returned as it is.
print(user:check({ name = "Ada", age = 36 }).name)
-- Prints: false	true
-- /age	minimum	the value is less than 0
-- /name	min_length	the string is shorter than 1
-- Ada
