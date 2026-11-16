local M = {}
function M.pick(n)
  if n > 0 then
    return "positive"
  end
  return "other"
end
return M
