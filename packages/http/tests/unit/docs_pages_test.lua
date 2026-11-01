-- The documentation must not drift from the code: the refusal table of the forms page is compared with the real map of
-- `FormError` reasons and statuses.
local test = require("harness.test")
local form = require("hecate.http.form")
local T = test.Case("DocsPagesTest")

local here = debug.getinfo(1, "S").source:sub(2):gsub("\\", "/")
local root = here:match("^(.*)/packages/http/tests/unit/")

local function read(path)
  local file = assert(io.open(root .. "/" .. path, "rb"), "missing " .. path)
  local text = file:read("a")
  file:close()
  return text
end

function T:test_the_forms_page_lists_every_form_error_reason_with_its_real_status()
  local text = read("website/en/how-to/handle-forms-and-multipart.md")
  local section = text:match("## Refusals(.-)\n## ") or text:match("## Refusals(.*)$")
  self:assert_not_nil(section, "the page has a Refusals section")
  local documented = {}
  for reasons, status in section:gmatch("\n|([^|\n]+)|%s*(%d+)%s*|") do
    for reason in reasons:gmatch("`([%w_]+)`") do
      self:assert_nil(documented[reason], "listed twice: " .. reason)
      documented[reason] = tonumber(status)
    end
  end
  for reason, status in pairs(form.REASONS) do
    self:assert_equal(status, documented[reason], "the page and the code disagree on " .. reason)
  end
  for reason in pairs(documented) do
    self:assert_not_nil(form.REASONS[reason], "the page lists a reason the code does not have: " .. reason)
  end
end

function T:test_every_reason_builds_an_error_with_its_status_and_an_unknown_one_is_refused()
  for reason, status in pairs(form.REASONS) do
    local err = form.failure(reason, "x")
    self:assert_equal(status, err.context.status)
    self:assert_equal(reason, err.context.reason)
  end
  self:assert_error(function() form.failure("not_a_reason", "x") end)
end

return T
