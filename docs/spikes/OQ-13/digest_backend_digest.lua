-- Backend over the `digest` rock (C, one source file, MIT AND BSD-3-Clause): fast, streams, no other rock.
local digest = require("digest")

return {
  name = "digest",
  sha256 = function(data) return digest.sha256hex(data) end,
  sha256_file = function(path)
    local f, err = io.open(path, "rb")
    if not f then return nil, err end
    local ctx = digest.new("sha256")
    for chunk in function() return f:read(65536) end do ctx:add(chunk) end
    f:close()
    return ctx:hexdigest()
  end,
}
