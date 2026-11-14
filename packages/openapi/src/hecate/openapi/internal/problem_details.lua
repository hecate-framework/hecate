-- The problem details component (RFC 9457 section 3.1): the schema that error responses reference, and the media
-- type they use (RFC 9457 section 6.1).
global <const> require, type

local core = require("hecate.core")

--- The problem details schema and media type.
---@class hecate.openapi.problem_details
local problem_details = {}

--- The component name.
problem_details.NAME = "ProblemDetails"

--- The media type of a problem details response (RFC 9457 section 6.1).
problem_details.MEDIA_TYPE = "application/problem+json"

--- The Schema Object of a problem details object. The five members are those of RFC 9457 section 3.1; extension
--- members are allowed (section 3.2), hence no `additionalProperties: false`.
---@return table
function problem_details.schema()
  return {
    type = "object",
    description = "A problem details object (RFC 9457).",
    properties = {
      type = { type = "string", format = "uri-reference", default = "about:blank",
        description = "A URI reference that identifies the problem type (RFC 9457 section 3.1.1)." },
      title = { type = "string", description = "A short, human-readable summary of the problem type (section 3.1.3)." },
      status = { type = "integer", minimum = 100, maximum = 599,
        description = "The HTTP status code of this occurrence (section 3.1.2)." },
      detail = { type = "string", description = "An explanation specific to this occurrence (section 3.1.4)." },
      instance = { type = "string", format = "uri-reference", description = "A URI reference that identifies this occurrence (section 3.1.5)." },
    },
    additionalProperties = true,
  }
end

--- Tells whether a response declaration is a problem class: a class that implements the marker interface
--- `core.Problem` (a subclass inherits the declaration). The class attributes `status` and `title` are read and
--- validated by the caller (OQ-129 (7), (12)).
---@param value any
---@return boolean
function problem_details.is_class(value)
  return type(value) == "table" and core.implements(value, core.Problem)
end

return problem_details
