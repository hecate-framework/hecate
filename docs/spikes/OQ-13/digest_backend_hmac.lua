-- Backend over the `hmac` rock (C, MIT): about 80 times faster, streams, needs native linking.
local hmac = require("hmac")

return {
  name = "hmac",
  sha256 = function(data)
    local ctx = hmac.sha256()
    ctx:update(data)
    return ctx:final() -- lowercase hexadecimal already
  end,
  sha256_file = function(path)
    local f, err = io.open(path, "rb")
    if not f then return nil, err end
    local ctx = hmac.sha256()
    for chunk in function() return f:read(65536) end do ctx:update(chunk) end
    f:close()
    return ctx:final()
  end,
}
