---
description: The commands of the hecate executable - what each one does, its options and its exit codes.
hecate: "0.x"
lua: "5.5"
order: 5
---

# The `hecate` command

`hecate` is one executable that embeds Lua 5.5, LuaRocks and what the command line needs. It is the interpreter of a Lua
5.5 project: it runs the project's code in a child process with the project's modules on the path, so a machine needs no Lua
or LuaRocks of its own. This page lists the commands; `hecate <command> --help` prints the options of one, and every command
accepts `--json` for a machine-readable result. An exit status of `0` is success, `1` a failure of the command or of what it
ran, and `2` a usage error.

## Projects

| Command | What it does |
|---|---|
| `hecate new <name> [--template api\|minimal] [--ci github]` | Creates the directory `<name>` from a template and refuses one that exists. `--ci github` also writes `.github/workflows/ci.yml` (see `hecate generate workflow`). `api` (the default) is a health check and a resource with its schemas, route module and tests; `minimal` is the health check alone. Both write the manifest (with the `doc` layout), `main.lua`, `config/development.lua` and `config/test.lua`, the tests and a first documentation page. |
| `hecate init [--name <name>]` | Adds the `minimal` template to the current directory, keeping every file that exists. |
| `hecate doctor` | Checks the environment: Lua, LuaRocks, libuv, the native modules, a C compiler. In a project, it also compares the version of the executable with the `hecate.core` the project uses, and warns (without failing) when they differ: run `hecate install` or update the executable. |
| `hecate version` | Prints the Hecate, Lua, LuaRocks and libuv versions and the platform. |
| `hecate completion bash\|zsh\|fish\|powershell` | Prints the completion script of a shell. |

## Dependencies

The dependencies of a project are rocks, listed in `hecate.project.lua` and locked in `hecate.lock` (commit it).

| Command | What it does |
|---|---|
| `hecate install [--frozen]` | Installs the dependencies into `lua_modules` and writes `hecate.lock`. With `--frozen` it installs exactly what the lock says and fails when the manifest and the lock differ, or when an installed file differs from its recorded checksum. Rocks with C code build with the headers of the embedded Lua, so no system Lua is needed. |
| `hecate add <rock>[@constraint] [--dev]` | Adds a dependency to the manifest (the constraint defaults to `~> major.minor` of the installed version; `--dev` adds it to `development_dependencies`), installs it and updates the lock. |
| `hecate remove <rock>` | Removes a dependency from the manifest and updates the lock. |
| `hecate outdated` | Lists the rocks that have a newer version and whether the manifest's constraint allows it. |
| `hecate update [<rock>]` | Takes the newest versions the constraints allow and rewrites the lock. |

`rocks_servers` in the manifest lists extra LuaRocks servers, consulted before luarocks.org.

## Running and testing

| Command | What it does |
|---|---|
| `hecate serve [--watch] [--workers <n>] [--env <name>]` | Runs `main.lua` in a child process. `--watch` restarts it when a `.lua` file of `src`, `config` or `main.lua` changes. `--workers` sets `HECATE_SERVER__WORKERS` (a number or `auto`); `--env` sets `HECATE_ENV` (for example `development`; without it the variable is left as it is, and then the environment is `production`). Ctrl+C and `SIGTERM` stop the application gracefully. |
| `hecate run <script> [--env <name>] [-- <arguments>]` | Runs a script of the project: a name from `scripts` in the manifest, or a `.lua` file inside the project. Arguments for it follow `--`. |
| `hecate test [<path>...] [--filter <pattern>] [--case <name>] [--tag <tag>] [--exclude-tag <tag>] [--jobs <n>]` | Runs the tests of the project (default `tests/`) with the project's dependencies on the module path. `--jobs` runs the test files in that many worker processes. |

## Contract and documentation

| Command | What it does |
|---|---|
| `hecate contract export [--output <file>] [--pretty]` | Writes the OpenAPI 3.1 document of the application (the module named like the project must have `application(options)`; the manifest's `contract` section gives the title and version). |
| `hecate contract lint <file>` | Lints an OpenAPI document; exit `1` on an error finding. |
| `hecate contract diff <old> <new>` or `<ref>` | Lists the changes between two documents, or between the `openapi.json` of a git ref (read with `git show`; `--file` names another file) and the application now; exit `1` on a breaking change. |
| `hecate doc build [--audience <name>] [--output <dir>] [--yes]` | Builds the documentation site of the project into `docs/dist`. When the project asks for a code reference, LuaLS runs the plugins its configuration declares, so the command asks first (`--yes` answers for CI). |
| `hecate generate meta [--namespace <name>] [--output <file>] [--force]` | Writes the LuaLS declaration file of the schemas of the contract, `meta/<module>.schemas.lua` by default; list `meta` in `workspace.library` of `.luarc.json`. `--force` overwrites an existing output file after printing the unified diff of the existing and the new content (`unchanged`, and no rewrite, when they are equal; with `--json` the diff is the `diff` field). |

## Delivery

| Command | What it does |
|---|---|
| `hecate package [--output <file>]` | Writes the release archive of the project and its `.sha256`: the manifest, the lock, `main.lua`, `src`, `config`, `lua_modules` and a `RELEASE` file. Run `hecate install --frozen` first, on the platform of the server. See [Deliver to a server](../how-to/deliver-to-a-server.md). |
| `hecate generate systemd [--user <name>] [--workers <n>] [--working-directory <dir>] [--environment-file <file>] [--executable <path>] [--output <file>] [--force]` | Prints, or writes, the systemd unit that runs `hecate serve`: it stops on `SIGTERM` and reloads on `SIGHUP`. `--working-directory` and `--environment-file` are paths on the server (absolute); a value with a line break is refused. `--force` overwrites an existing output file after printing the unified diff of the existing and the new content (`unchanged`, and no rewrite, when they are equal; with `--json` the diff is the `diff` field). |
| `hecate generate workflow <ci\|contract\|docs-pages> [--provider github] [--doc] [--output <file>] [--force]` | Writes a workflow of the project, `.github/workflows/<kind>.yml` by default (`docs.yml` for `docs-pages`), and keeps an existing file unless `--force`, which prints the unified diff of the existing and the new file, then overwrites (identical content: `unchanged`, nothing rewritten; with `--json` the diff is the `diff` field). `ci` runs on every push and pull request, on Linux, macOS and Windows: checkout, the setup action of Hecate (`hecate-framework/hecate-actions/setup`, `version` in the form `X.Y.Z-R`, for example `0.4.0-1`, or `0.4.2rc1-1` for a pre-release), `hecate install --frozen`, `hecate test`, then `hecate contract export` and `hecate contract lint` when the manifest has a `contract` section, and `hecate doc build --yes` with `--doc`. `contract` (needs a `contract` section) runs on pull requests with the whole history and runs `hecate contract diff origin/<base branch>`, which fails on a breaking change: `openapi.json` must be committed on the base branch. `docs-pages` runs on a push to the default branch, builds the documentation with `hecate doc build --yes` and publishes `docs/dist` to GitHub Pages (set the source of Pages to "GitHub Actions"; the site has relative links, so it needs no base path). The `release` kind of the specification is not implemented yet. See [Deliver to a server](../how-to/deliver-to-a-server.md). |

## The manifest

`hecate.project.lua` is a Lua file that returns a table, read with no globals. Its keys: `name`, `version`, `description`,
`license`, `lua`, `dependencies`, `development_dependencies`, `scripts`, `rocks_servers`, `contract` (`title`, `version`,
`servers`) and `doc` (`guides_dir`, `output_dir`, `sources_dir`, `package_name`, `site_configuration_path`). See
[Create and run a project](../how-to/create-and-run-a-project.md) for a tour.
