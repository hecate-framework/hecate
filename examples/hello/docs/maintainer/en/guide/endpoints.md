---
description: The three routes of hello, their input and their answers.
hecate: "0.x"
lua: "5.5"
order: 2
---

# Endpoints

The two greeting routes are declared by a controller, `/health` by a route module. Both declaration styles
produce the same routes in the route table.

## Greet a name

`GET /hello/{name}` takes a path parameter of 1 to 40 characters and answers `200`.

```sh
curl -s localhost:8080/hello/Ada
```

```json
{ "message": "Hello, Ada!" }
```

## Record a greeting

`POST /greetings` takes JSON content. `name` is required (1 to 40 characters); `language` is optional, two
letters, and defaults to `en`.

```sh
curl -s -X POST localhost:8080/greetings \
  -H 'Content-Type: application/json' \
  -d '{"name":"Ada","language":"fr"}'
```

The answer is `201` with the identifier of the greeting and its text.

```json
{ "id": 1, "message": "Bonjour, Ada!" }
```

The controller declares the route and its action:

```lua
hecate.Controller.route(GreetingController, {
  method = "POST", path = "/greetings", name = "greeting.create",
  action = "create", summary = "Records a greeting",
  content = { ["application/json"] = NewGreeting },
  responses = { [201] = Created, [422] = hecate.problem.UnprocessableContent },
})
```

## Health check

`GET /health` is declared by a route module, the lightweight style.

```lua
health:get("/health", {
  name = "health.check",
  summary = "Liveness probe",
  responses = { [200] = schema.object({ status = schema.string() }) },
  action = function() return { status = "ok" } end,
})
```

## Unknown paths

Any other path answers `404` problem details.
