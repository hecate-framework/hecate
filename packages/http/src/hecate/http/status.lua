-- Status codes and reason phrases (RFC 9110, section 15). The table lives in `hecate.core.status`, shared with
-- `hecate.openapi` and the problem classes (OQ-129 (12)); `hecate.http.Status` is kept as an alias of it.
global <const> require

local core_status = require("hecate.core").status

--- Registered status codes (RFC 9110, section 15; IANA registry) with their reason phrases: an alias of
--- `hecate.core.status` (`reason`, `is_valid`, `is_error`, `class`, `forbids_content`).
---@class hecate.http.Status : hecate.core.status
local Status = core_status

return Status
