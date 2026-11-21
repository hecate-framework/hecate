---
description: Start the hello server, with worker processes, and stop it.
hecate: "0.x"
lua: "5.5"
order: 5
---

# Running it

From `examples/hello`, with the hecate packages on the search path (the README of the example gives the
commands):

```sh
HELLO_PORT=8080 lua main.lua
HELLO_PORT=8080 HELLO_WORKERS=4 lua main.lua
```

| Variable | Default | Effect |
|---|---|---|
| `HELLO_PORT` | `8080` | Port on the loopback interface. |
| `HELLO_WORKERS` | `1` | Above 1, the process supervises that many workers. |

Ctrl+C or SIGTERM stops accepting connections, lets the requests in flight finish within 10 seconds, and exits.

## Build this documentation

```sh
lua examples/hello/build_docs.lua
```

The site is written to `examples/hello/docs/dist/maintainer`, which is git-ignored.
