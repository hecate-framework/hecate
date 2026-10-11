# CLI and packaging (`hecate.cli`)

Status: specification; [ADR 0009](../adr/0009-project-manifest.md) and
[ADR 0010](../adr/0010-self-contained-cli-and-managed-toolchains.md) (both Accepted).

## Principles

- One tool for the whole life cycle: toolchain, project, dependencies, development
  server, tests, contracts, documentation, database, packaging.
- LuaRocks is the package backend, used extensively and transparently; Hecate never
  forks the rock format.
- Every command supports `--help`, `--json` (machine-readable output for CI and
  agents) and meaningful exit codes.

## Commands

| Command | Purpose |
|---|---|
| `hecate new <name> [--template api\|minimal\|crud]` | create a project from a template; installs the toolchain if needed |
| `hecate init` | add Hecate to an existing directory |
| `hecate install [--frozen]` | install dependencies from manifest + lockfile (`--frozen` fails if the lockfile is outdated) |
| `hecate add <rock>[@constraint] [--dev]` / `hecate remove <rock>` | edit manifest, resolve, install, update lockfile |
| `hecate update [<rock>]` | update within constraints |
| `hecate outdated` | list newer versions |
| `hecate audit` | check dependencies against the advisory database (planned) |
| `hecate serve [--watch] [--workers N]` | run the application; reload on change in development |
| `hecate run <script>` | run a script declared in the manifest or a Lua file inside the project environment |
| `hecate repl` | Lua 5.5 REPL with the project on the path, inside a reactor |
| `hecate test [filters]` | run tests (see testing.md) |
| `hecate check` | format check, lint, LuaLS type check, configuration validation, route table validation |
| `hecate format` | format sources |
| `hecate routes` | print the route table |
| `hecate contract export\|diff\|lint` | OpenAPI document, breaking-change detection, lint |
| `hecate doc build\|serve` | project documentation |
| `hecate migrate [status\|new\|rollback]` | database migrations |
| `hecate generate <kind> <name>` | scaffold a controller, entity, repository, route module, migration, test case |
| `hecate package` | generate a rockspec from the manifest and pack a rock |
| `hecate publish` | publish to luarocks.org (or a configured server) |
| `hecate toolchain install\|list\|use\|remove` | manage Lua + LuaRocks toolchains |
| `hecate docker init` | generate a Dockerfile based on official images |
| `hecate generate workflow <kind> [--provider github]` | generate CI/CD workflows for the project: `ci` (install, check, test on Linux/macOS/Windows), `contract` (export, lint and diff against the base branch), `docs-pages` (build the documentation with `hecate doc build` and publish it to the repository's GitHub Pages), `release` (package and publish rocks) |
| `hecate doctor` | diagnose the environment: versions, compilers, OpenSSL, libuv, PATH |
| `hecate version` | `Hecate 0.3.0 (Lua 5.5.1, LuaRocks 3.x, libuv 1.x) — linux-x86_64` |
| `hecate self update` | update the CLI |

## Manifest: `hecate.project.lua`

Evaluated in an empty environment (no globals, no `require`), with an instruction
limit. Schema (validated with `hecate.schema`):

```lua
return {
  name        = "acme-api",          -- required
  version     = "0.1.0",             -- SemVer
  description = "ACME public API",
  license     = "MIT",
  lua         = "5.5",               -- Lua line; the toolchain is installed accordingly
  hecate      = "~> 0.3",            -- expected Hecate line (warns on mismatch)

  dependencies = {
    ["hecate"]            = "~> 0.3",
    ["hecate-postgresql"] = "~> 0.3",
  },
  development_dependencies = {
    ["hecate-test"] = "~> 0.3",
  },

  scripts = {
    seed = "scripts/seed.lua",
  },

  contract = {                       -- feeds OpenAPI `info`, `servers`, security
    title   = "ACME API",
    version = "1.0.0",
    servers = { "https://api.acme.example" },
  },

  rocks_servers = { },               -- extra LuaRocks servers, optional
}
```

## Lockfile: `hecate.lock`

Lua table, generated, sorted, diff-friendly. Records for each rock: name, exact
version, source URL, checksum (SHA-256), dependency edges, and whether it is a
development dependency; plus the Lua version, LuaRocks version and platform-independent
flag for native rocks.

## Environment layout

```text
<project>/
  lua_modules/      project-local LuaRocks tree (git-ignored)
  .hecate/          caches, generated LuaLS meta files, build artefacts (git-ignored)
~/.hecate/          (Windows: %LOCALAPPDATA%\hecate)
  toolchains/lua-5.5.1/      Lua + headers + LuaRocks
  cache/rocks/
```

The CLI runs LuaRocks with an isolated configuration pointing to the project tree and
the selected toolchain, so user and system LuaRocks configurations never interfere.

## Generated workflows

`hecate generate workflow` writes `.github/workflows/<kind>.yml` from templates in
`packages/cli/templates/workflows/`. Generated workflows:

- call only `hecate` commands, so they behave like local runs;
- install the CLI with the official setup action of the project (to be created with the
  CLI release) and cache the toolchain and the rocks tree;
- pin third-party actions by commit SHA;
- carry a header naming the template and Hecate version, and are regenerated with
  `--force` after an upgrade (a diff is shown first).

`docs-pages` uses the standard GitHub Pages actions (configure, upload artefact,
deploy), deploys from the default branch, supports a custom domain (`CNAME`) and sets
the base URL for project sites (`https://<owner>.github.io/<repository>/`). It needs
GitHub Pages set to "GitHub Actions" as source; the command prints that step.

The Hecate monorepo dogfoods these templates: its `website.yml` is generated by
`hecate generate workflow docs-pages` once the CLI exists.

## Templates

`api` (default: controllers, schemas, tests, Dockerfile; `--ci github` also generates
the `ci`, `contract` and `docs-pages` workflows), `minimal` (single route
module), `crud` (PostgreSQL, ORM, migrations). Templates live in
`packages/cli/templates/` and are tested in CI by generating and testing a project.
