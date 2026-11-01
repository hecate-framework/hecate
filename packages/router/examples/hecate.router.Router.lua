-- Declare routes as data, compile them once, match requests and build URLs from route names.
local router = require("hecate.router")

local routes = router.Router({
  { method = "GET", path = "/users", name = "users.list" },
  { method = "GET", path = "/users/{id}", name = "users.show" },
  { method = "DELETE", path = "/users/{id}", name = "users.delete" },
  { method = "GET", path = "/users/me", name = "users.me" },
  { method = "GET", path = "/static/{path...}", name = "static" },
})

local function show(method, path)
  local match = routes:match(method, path)
  if match.status == 200 then
    print(method, path, match.route.name, match.parameters.id or match.parameters.path or "-")
  else
    print(method, path, match.status, match.allow_field or "-")
  end
end

show("GET", "/users/42")
show("GET", "/users/me")
show("DELETE", "/users/me")
show("POST", "/users/42")
show("GET", "/static/css/site.css")
show("GET", "/nothing")
print(routes:url_for("users.show", { id = "Ada Lovelace" }))
-- Prints: GET	/users/42	users.show	42
-- GET	/users/me	users.me	-
-- DELETE	/users/me	users.delete	me
-- POST	/users/42	405	DELETE, GET, HEAD, OPTIONS
-- GET	/static/css/site.css	static	css/site.css
-- GET	/nothing	404	-
-- /users/Ada%20Lovelace
