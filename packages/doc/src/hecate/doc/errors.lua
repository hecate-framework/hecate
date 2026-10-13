-- Error classes of hecate.doc.
global <const> require

local core = require("hecate.core")

local errors = {}

--- Raised when a site cannot be built: malformed front matter, an unreadable source, a
--- broken link in strict mode. `context` carries the `path` and, where relevant, the line.
---@class hecate.doc.BuildError : hecate.core.Error
errors.BuildError = core.error_class("BuildError", "hecate.doc.BuildError")

return errors
