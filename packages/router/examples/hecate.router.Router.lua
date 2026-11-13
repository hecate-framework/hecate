-- Declare routes as data, compile them once, match requests and build URLs
-- from route names.
local router = require("hecate.router")

local routes = router.Router({
  { method = "GET", path = "/users", name = "users.list" },
  { method = "GET", path = "/users/{id}", name = "users.show" },
  { method = "DELETE", path = "/users/{id}", name = "users.delete" },
  { method = "GET", path = "/users/me", name = "users.me" },
  { method = "GET", path = "/static/{path...}", name = "static" },
})

-- A match carries the route and its parameters, or the status to answer.
local function show(method, path)
  local match = routes:match(method, path)
  if match.status == 200 then
    return method, path, match.route.name, match.parameters.id or match.parameters.path or "-"
  end
  return method, path, match.status, match.allow_field or "-"
end

print(show("GET", "/users/42"))
-- Prints: GET	/users/42	users.show	42
print(show("GET", "/users/me"))
-- Prints: GET	/users/me	users.me	-
print(show("DELETE", "/users/me"))
-- Prints: DELETE	/users/me	users.delete	me
print(show("POST", "/users/42"))
-- Prints: POST	/users/42	405	DELETE, GET, HEAD, OPTIONS
print(show("GET", "/static/css/site.css"))
-- Prints: GET	/static/css/site.css	static	css/site.css
print(show("GET", "/nothing"))
-- Prints: GET	/nothing	404	-
print(routes:url_for("users.show", { id = "Ada Lovelace" }))
-- Prints: /users/Ada%20Lovelace
