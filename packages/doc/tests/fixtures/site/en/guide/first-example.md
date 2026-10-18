---
title: A first runnable example
description: A pure-Lua example using hecate.core classes.
hecate: "0.x"
lua: "5.5"
order: 3
---

Classes come from `hecate.core`. This example is pure Lua.

```lua
local core = require("hecate.core")

---@class Greeter
local Greeter = core.class("Greeter")

function Greeter:init(name) self.name = name end
function Greeter:greet() return "Hello, " .. self.name end -- 5.5: `global` is also available
core.finalise(Greeter)

print(Greeter("hecate"):greet())
```

Expected output:

```text
Hello, hecate
```

Run it from a shell:

```sh
$ lua example.lua --verbose | tee "out.txt"  # prints the greeting
```

A request and its response:

```http
GET /users/42 HTTP/1.1
Accept: application/json
```

```json
{ "id": 42, "name": "Ada", "active": true, "score": 1.5e2 }
```

![A diagram](diagram.svg)

- [x] Install Lua 5.5
- [ ] Read the reference

1. First
2. Second
   - nested item
3. Third

Escaping is safe by default: <script>alert("x")</script> is shown as text, and
[a bad link](javascript:alert(1)) renders as plain text.
