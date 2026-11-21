---
description: What happens to a request between the socket and the action.
hecate: "0.x"
lua: "5.5"
order: 4
---

# Request flow

A request is parsed, routed, validated, then handed to the action. A validation failure never reaches the action.

```mermaid
flowchart LR
  socket[Socket] --> parse[Parse HTTP]
  parse --> route{Route found?}
  route -- no --> notfound[404 problem details]
  route -- yes --> validate{Input valid?}
  validate -- no --> invalid[422 problem details]
  validate -- yes --> action[Action]
  action --> respond[Response schema]
```

The route table is built once at start. The router matches the method and the path template; the dispatcher then
validates the path parameters and the content against the schemas of the route before it calls the action.
