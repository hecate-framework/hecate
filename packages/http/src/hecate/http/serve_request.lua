-- The in-process request-serving seam (OQ-78): runs an action on a request without a socket, checks what it returned and maps a
-- failure to problem details. The socket `Server` calls this function, so tests, the in-process client of `test` and the
-- kernel share the code path of production. It never serialises (OQ-76 a): a table as content is an error.
-- Needs no native module.
global <const> require, type, error, pcall

local core = require("hecate.core")
local Response = require("hecate.http.response")
local problem = require("hecate.http.problem")
local Status = require("hecate.http.status")
local Fields = require("hecate.http.fields")

local function is_cancellation(err) return core.is_instance_of(err, core.CancellationError) end

--- Runs `action(request)` and returns the response to send and the failure that was caught (nil when there was none).
--- The caller logs the failure: the server with its logger, a test client may ignore it. A failure and an action that
--- returns something the server cannot send (not a `Response`, a status below 200 or outside 599, invalid fields or
--- reason, content that is not nil, a string or a function, a table included) both give the generic 500 problem details
--- response; an error of the action maps by its class (`hecate.http.problem.of_error`). Nothing of the message of the
--- error reaches the response. A cancellation is raised again, never mapped.
---
--- The action runs in the calling computation, so it may suspend: the server calls it in the computation of the request.
---@async
---@param action fun(request: hecate.http.Request): hecate.http.Response
---@param request hecate.http.Request
---@return hecate.http.Response response
---@return any? failure  the error that was replaced by a problem response, or nil
local function serve_request(action, request)
  local ok, result = pcall(action, request)
  if not ok then
    if is_cancellation(result) then error(result, 0) end
    return problem.from_error(result), result
  end
  if not core.is_instance_of(result, Response) then
    return problem.response(500), core.Error("http.serve_request: the action returned " .. type(result) .. " instead of a Response")
  end
  local content = result.content
  local kind = type(content)
  if not Status.is_valid(result.status) or not core.is_instance_of(result.fields, Fields) or type(result.reason) ~= "string" then
    return problem.response(500), core.Error("http.serve_request: the action returned a response with an invalid status, reason or fields")
  end
  if kind == "table" then
    return problem.response(500), core.Error("http.serve_request: the action returned a table as content: http does not serialise (serialise it before)")
  end
  if result.status < 200 or not (content == nil or kind == "string" or kind == "function") then
    return problem.response(500), core.Error("http.serve_request: the action returned a response that cannot be sent")
  end
  return result, nil
end

return serve_request
