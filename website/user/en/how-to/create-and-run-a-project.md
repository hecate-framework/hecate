---
description: Create a hecate project, install its dependencies, run it, test it, export its contract, build its documentation and keep its dependencies up to date, all with the hecate command.
hecate: "0.x"
lua: "5.5"
order: 5
---

# Create and run a project

This guide takes a new project from nothing to a tested, documented API with the [`hecate` command](../reference/cli.md).
It is written for hecate 0.x and Lua 5.5. You need the `hecate` executable and nothing else: no Lua, no LuaRocks.

## Create it

```sh
hecate new shop
cd shop
hecate install
```

`hecate new` writes a project with a health check and an `items` resource: `hecate.project.lua` (the manifest),
`main.lua` (starts the application), `src/shop/` (the application, its schemas and routes), `tests/`, `config/` and
`docs/`. `hecate install` puts the dependencies in `lua_modules` and writes `hecate.lock`; commit the lock, and use
`hecate install --frozen` in CI to get exactly what it says.

## Run it and test it

```sh
hecate test
hecate serve --env development
```

`hecate test` runs `tests/` with the project's modules on the path; `--jobs 4` runs the files in four worker processes.
`hecate serve` runs `main.lua` (port from `PORT`, default 8080) and stops gracefully on Ctrl+C. `--env development`
chooses the [configuration](configure-an-application.md) environment: the generated `config/development.lua` and
`config/test.lua` run one process, while the default `production` environment starts one worker per core minus one
(`--workers 2` chooses the number). `--watch` restarts the application when the sources change.

## Check the contract

```sh
hecate contract export --output openapi.json
hecate contract lint openapi.json
hecate generate meta
```

The first command writes the [contract](serve-and-export-the-contract.md) of the application (the manifest's `contract`
section gives its title and version), the second lints it and exits `1` on an error. Commit `openapi.json` and
`hecate contract diff <ref>` tells you what a change broke since that git ref. `hecate generate meta` writes
`meta/shop.schemas.lua`, the declaration file that lets an editor know the types of the schemas.

## Build the documentation

```sh
hecate doc build --yes
```

The site goes to `docs/dist`: one folder of static files per audience, built from the Markdown pages of `docs/` and the
code reference of `src/`. The files need no server: open `docs/dist/index.html` from the file system, or publish the folder on any static host. The code reference runs LuaLS, which runs the plugin its configuration declares: build only a
project you trust, and answer the question (or pass `--yes`) knowingly.

## Keep the dependencies up to date

```sh
hecate add plc@"~> 0.5"
hecate outdated
hecate update
```

`add` and `remove` edit the manifest and the lock; `outdated` lists the rocks that have a newer version and whether your
constraints allow it; `update` takes the newest versions they allow. To deliver the result to a server, see
[Deliver to a server](deliver-to-a-server.md).
