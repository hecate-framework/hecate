---
description: Render the OpenAPI contract of an application in Swagger UI with Docker Compose - the application, a reverse proxy that gives both one origin, and a pinned viewer image.
hecate: "0.x"
lua: "5.5"
order: 25
---

# Render the contract with Docker Compose

The application serves only the JSON contract, `GET /openapi.json` (see [Serve and export the contract](serve-and-export-the-contract.md)).
It has no viewer page: a viewer is your own wiring. This guide is written for hecate 0.x and Lua 5.5 and shows one
wiring with three containers.

## Build the application image

Start from the runtime image and copy the application. It runs as the non-root user `hecate`.

```dockerfile
FROM hecate/runtime:latest
COPY --chown=hecate . /app
CMD ["lua", "main.lua"]
```

Inside a container the application must listen on `0.0.0.0`, not on `127.0.0.1`: set the `host` of the server
options of your `Application` accordingly.

## Run the stack

The files are `docker/compose/compose.yaml` and `docker/compose/nginx.conf` of the repository. Copy them next to your
Dockerfile, then:

```sh
docker compose up --build
```

Open `http://localhost:8080/docs/` for the viewer. The application answers on `http://localhost:8080/`.

## Why a proxy

A browser enforces the same-origin policy: a viewer served from another origin could read `/openapi.json` only if
the application sent CORS response fields. The proxy serves `/docs/` from the viewer and everything else from the application,
so both share one origin and no CORS configuration is needed.

## Make the contract available

The document is served by default only in the `development` environment. The compose file sets `HECATE_ENV=development`.
To serve it in another environment, give the `openapi` option `enabled = true` instead, and keep the route
unreachable from the internet: it describes every route of the application.

## Pin the images

Every image of the compose file is pinned by tag. Pin digests (`image: name@sha256:...`) for a deployment, and
update them on purpose.
