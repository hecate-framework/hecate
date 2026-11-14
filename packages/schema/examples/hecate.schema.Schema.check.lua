-- Report violations to a client: `check` raises a `ValidationError`, and its
-- violations become the `errors` of a problem details response (RFC 9457).
-- The kernel builds this 422 for you from the inputs of a request.
local core = require("hecate.core")
local schema = require("hecate.schema")

local user = schema.object({
  name = schema.string({ min_length = 1 }),
  age = schema.integer({ minimum = 0 }),
})

local ok, err = pcall(user.check, user, { name = "", age = -1 })
print(ok, core.is_instance_of(err, core.ValidationError))
-- Prints: false	true

-- The 422 of the kernel: one entry per violation, with the JSON Pointer of the
-- value and the stable code (the kernel adds the `source` of an input).
local problem = {
  type = "about:blank",
  title = "Unprocessable Content",
  status = 422,
  detail = "The request content does not conform to the contract.",
  errors = {},
}
for _, violation in ipairs(err.context.violations) do
  local entry = { pointer = violation.path, code = violation.code }
  problem.errors[#problem.errors + 1] = entry
end
for _, entry in ipairs(problem.errors) do
  print(entry.pointer, entry.code)
end
-- Prints: /age	minimum
-- /name	min_length

-- Each violation also has a message, with no client value in it. The kernel
-- adds it to the entries only when `errors.expose_details` is true.
print(err.context.violations[1].message)
-- Prints: the value is less than 0

-- A conforming value is returned as it is.
print(user:check({ name = "Ada", age = 36 }).name)
-- Prints: Ada
