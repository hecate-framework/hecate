---
description: Serve the OpenAPI 3.1 document of an application, export it as JSON from code, and lint it with hecate.openapi - the openapi option, its defaults and the rules of the lint.
hecate: "0.x"
lua: "5.5"
order: 20
---

# Serve and export the contract

The [contract](../reference/glossary.md) of an application is the OpenAPI 3.1 document that `hecate.openapi`
assembles from its route table. This guide is written for hecate 0.x and Lua 5.5, and assumes you know how to
[route requests](route-requests.md). Every route must have an explicit `name`: it becomes the `operationId`.

## Serve it

Give `hecate.kernel.Application` the `openapi` option. `info` is required.

```lua
local kernel = require("hecate.kernel")

local app = kernel.Application({
  routes = { health },
  openapi = { info = { title = "Shop", version = "1.0.0" } },
})
```

The document is served by `GET /openapi.json`, by default only in the `development` environment of the
configuration. Set `enabled = true` or `false` to override, and `path` or `name` to move the route. The route is not
part of the document, and the document is built at the first request, then kept.

## Export it

`Application:contract(pretty?)` returns the JSON text of the document of a booted application, served or not. The
output is canonical (RFC 8785 member order), so equal contracts give equal bytes and a diff of two exports is stable.

```lua
app:boot()
local file = assert(io.open("openapi.json", "wb"))
file:write(app:contract(true))
file:close()
```

Calling it before `boot`, or without the `openapi` option, raises `hecate.kernel.ModuleError` (`not_booted`,
`no_contract`). The `hecate contract export` command will wrap this call. Only JSON is written in 0.1.0.

## Lint and compare

`openapi.lint(document)` returns findings sorted by path and rule: errors (`operation-id-missing`,
`response-description-missing`, `response-undocumented`) and warnings (`description-missing`, `example-missing`,
`tag-unused`). `openapi.diff(old, new)` lists the changes between two documents and marks the breaking ones. Both take
decoded documents (`hecate.json.decode`).
