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
| `hecate doc build` | project documentation: static sites, one per audience (no development server: owner decision of 2026-11-24, see OQ-148) |
| `hecate migrate [status\|new\|rollback]` | database migrations |
| `hecate generate meta [--namespace <name>] [--output <file>] [--force]` | the LuaLS declaration file (`---@meta`) of the schemas of the contract of the application, `meta/<module>.schemas.lua` by default (OQ-121); on demand, never by another command |
| `hecate generate systemd [--user <name>] [--workers <n>] [--executable <path>] [--output <file>] [--force]` | the systemd unit that runs the application as a service (OQ-133) |
| `hecate generate <kind> <name>` | scaffold a controller, entity, repository, route module, migration, test case |
| `hecate package` | generate a rockspec from the manifest and pack a rock |
| `hecate publish` | publish to luarocks.org (or a configured server) |
| `hecate toolchain install\|list\|use\|remove` | manage Lua + LuaRocks toolchains |
| `hecate generate workflow <kind> [--provider github] [--doc] [--output <file>] [--force]` | (implemented: `ci`, `contract` and `docs-pages`; `release` is to do) generate CI/CD workflows for the project: `ci` (install, check, test on Linux/macOS/Windows), `contract` (on a pull request, diff the committed contract of the base branch against the application and fail on a breaking change), `docs-pages` (build the documentation with `hecate doc build` and publish it to the repository's GitHub Pages), `release` (package and publish rocks) |
| `hecate serve --env <name>`, `hecate run --env <name>` | set the configuration environment (`HECATE_ENV`) of the child: the flag, else `HECATE_ENV` as the process has it, else `production`; no value in `hecate.project.lua` (it would reach production by accident); a shorter `hecate dev` may come later (owner decision of 2026-11-24) |
| `hecate package [--output <file>]` | the release archive of the project for a server without Docker (owner agreement of 2026-11-24), see "Delivery to a server" |
| `hecate doctor` | diagnose the environment: versions, compilers, OpenSSL, libuv, PATH; in a project, the version skew between the executable (`hecate.cli.main.embedded_version()`) and the `hecate.core.version` the project resolves (a child process with the module path of the project): a difference is a warning that says to run `hecate install` or update the executable, and a project without `hecate.core` yet is an informational line |
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

## LuaRocks integration

Verified in [spike OQ-2](../spikes/OQ-2.md) with LuaRocks 3.13 on Lua 5.5. The CLI
wraps LuaRocks as follows:

- `luarocks.lock` stays the machine-read source of exact versions; `hecate.lock` adds
  checksums, sources and toolchain data. The `luarocks.lock` format is never changed.
- Install first, pin afterwards: `install --deps-only`, then `build --pin --only-deps`
  (pinning a fresh tree fails).
- Remove the `lua` pseudo-rock entry from the generated `luarocks.lock`; otherwise
  reinstalling from the lock prints an error and exits with status 1.
- Run every LuaRocks command with an explicit `--tree` and outside any directory holding
  a `luarocks.lock`, unless pinning is intended: a lock in the working directory applies
  to all commands.
- Judge success by the installed set, not by the exit status alone.
- On Windows the toolchain configures `LUA_LIBDIR` and the import library name, so that
  native rocks build.

## Formatter choice (proposed, OQ-3)

`hecate format` runs the formatter selected in `hecate.project.lua`; the choice is the
project's, not the framework's. Status of the candidates on Lua 5.5
([spike OQ-3](../spikes/OQ-3.md)):

| Formatter | Status |
|---|---|
| none | allowed; LuaLS still checks every Lua 5.5 construct |
| StyLua | cannot parse `global`, named varargs or prefix attributes yet; supported once upstream adds Lua 5.5 |
| EmmyLuaCodeStyle | stopgap, with the limitations below |

**Warning shown by `hecate format` and `hecate new` when EmmyLuaCodeStyle is selected,
and repeated in the website guide:**

- `global` declarations are **silently not formatted**: `global x = 1` is misparsed as an
  expression and left untouched, with no error.
- `global function f() end` and the prefix attribute `local <const> x` are syntax errors:
  the whole file is skipped (the command reports it and exits non-zero).
- Named varargs (`...name`) and the suffix attribute forms (`local x <const>`) format
  correctly.
- It is less opinionated than StyLua: expect different layout, and reformatting when
  switching formatter.
- Until the formatter supports them, avoid `global` declarations and prefix attributes
  in files it formats; `hecate check` (LuaLS) is unaffected.

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

> Decided ([ADR 0029](../adr/0029-executable-is-the-lua-5.5-interpreter.md)): the executable embeds Lua 5.5
> and LuaRocks and acts as the interpreter of a Lua 5.5 project, so `toolchains/lua-5.5.1/` is not downloaded; a
> toolchain is installed only for another Lua version. This section is rewritten with the `cli` v1 item.

> **`hecate toolchain` (owner direction of 2026-11-24): later.** Nothing is implemented before a second Lua line is
> supported (Lua 5.4, OQ-7). The direction for that time: Hecate ships its own already compiled toolchains, one per
> platform, architecture and Lua version, built and tested in CI by the project, rather than compiling Lua on the user's
> machine, so that switching interpreters (`hecate toolchain use`) gives a combination known to work. Where the archives
> are published and stored (the releases of the monorepo are the natural place) and how they are verified (the
> `sha256` of each archive in the release notes and in the CLI) is decided when the item starts.

> **Headers for C rocks (owner decision of 2026-11-24).** The executable carries the `lua.h`, `luaconf.h`, `lualib.h`
> and `lauxlib.h` of its embedded Lua. `hecate install` unpacks them into `.hecate/lua/include` and points the
> `LUA_INCDIR` variable of the isolated LuaRocks configuration at that directory, so that a rock with C code builds
> with no system Lua. On Windows `LUA_LIBDIR` and the import library come with the `lua55.dll` beside the executable.

## Generated workflows

`hecate generate workflow` writes `.github/workflows/<kind>.yml` from templates in
`packages/cli/src/hecate/cli/templates/workflows.lua`. Generated workflows:

- call only `hecate` commands, so they behave like local runs;
- install the CLI with the official setup action of the project (`packages/actions/setup/`, below) and cache the rocks tree
  (`lua_modules`, keyed by the hash of `hecate.lock`);
- pin third-party actions by commit SHA;
- carry a header naming the template and Hecate version, and are regenerated with
  `--force` after an upgrade (the unified diff of the existing and the new file is shown first, then the file is overwritten; identical content is reported as unchanged and not rewritten).

`docs-pages` uses the standard GitHub Pages actions (configure, upload artefact,
deploy), deploys on a push to the default branch and supports a custom domain (`CNAME`). The documentation site is
static with relative links (OQ-148), so the workflow sets no base path. It needs GitHub Pages set to "GitHub Actions" as
source; the command prints that step.

`contract` runs on pull requests, on Linux, with the whole history (`fetch-depth: 0`): `hecate contract diff
origin/<base branch>` compares the `openapi.json` committed on the base branch with the contract of the application of
the pull request and exits 1 on a breaking change. It needs a project with a `contract` section (the command refuses
otherwise) and `openapi.json` committed on the base branch.

The setup action is released like any GitHub Action (owner direction of 2026-11-24): a package of its own
(owner decision of 2026-11-25: the package `actions`, `packages/actions/`, which is no Lua rock and has the `Kind | actions` row in its README so that the tools exempt it from the rockspec, version and layer checks; the action is `packages/actions/setup/action.yml`, published with the whole package to the generated read-only mirror `hecate-framework/hecate-actions`, ADR 0017, where it stays at `setup/action.yml`, the path GitHub resolves for a `uses:` that names a directory of a repository; the action installs the executable of a given release and puts it on the `PATH`; `uses: hecate-framework/hecate-actions/setup@<ref>`), the tags of Hecate and of the mirror of the package have no `v` and follow the LuaRocks version form `<version>-<revision>` (`0.1.0-1`; owner, 2026-11-25), each with a GitHub Release, and there is no moving major tag; a user pins a tag or, as the generated workflows do, a commit SHA with the tag
in a comment. The release process of Hecate (`release-manager`, the `release` workflow) publishes the executable first,
then tags the action for it, and updates in the same release the commit SHA of the action that the templates of
`hecate generate workflow` write, so that a project generated by a release uses the setup action of that release.

Implemented: the `ci` workflow (push and pull request; Linux, macOS, Windows; checkout, setup, `hecate install --frozen`,
`hecate test`, `hecate contract export` and `lint` when the manifest has a `contract` section, `hecate doc build --yes`
with `--doc`), and `hecate new --ci github`, which writes it for the `api` and `minimal` templates. `packages/actions/setup/` is a
composite action (`version`, `repository` inputs): it downloads `hecate-<version>-<os>-<architecture>.tar.gz` (`.zip` on
Windows; `os` is `linux`, `darwin` or `windows`, `architecture` `x86_64` or `aarch64`; `<version>` is the whole `X.Y.Z[pre]-R`, executable at the archive root, `lua55.dll` beside `hecate.exe` on Windows) from the release `<version>` (the tag, no `v`) of
`hecate-framework/hecate`, verifies it against its `<asset>.sha256` (`<hex>  <archive name>`), refuses on a mismatch, and puts the directory on the `PATH`.
The `version` input is `X.Y.Z[pre]-R` (the grammar of "Releases"; anything else is refused, a leading `v` included) and the `hecate version` check compares the `X.Y.Z[pre]` part (`hecate version` prints the content of `VERSION`). The generated workflows write `version: "<hecate_version>-<REVISION>"` (`REVISION`, a constant of the same module, is `1`) and name `hecate-framework/hecate-actions/setup@<tag>`, where the tag is the constant
`hecate.cli.templates.workflows.SETUP_REF`, a placeholder (`0.0.0-1`) that the release process replaces (OQ-149). The `contract`
kind (`contract.yml`) and the `docs-pages` kind (`docs.yml`: setup, `hecate install --frozen`, `hecate doc build --yes`, then
configure, upload (`docs/dist`) and deploy with the Pages actions pinned by commit SHA; permissions `contents: read`,
`pages: write`, `id-token: write`) are implemented as described above. Not
implemented yet: the `release` kind (owner gate: releases and installers), and the cache
of the toolchain (there is none to cache: the executable is the interpreter, ADR 0029).

The service of a project in production is generated by `hecate generate systemd` (OQ-133, owner decision of
2026-11-24 for the name): a unit that runs `hecate serve`, stops on `SIGTERM` and reloads on `SIGHUP`.

The Hecate monorepo dogfoods these templates: its `website.yml` is generated by
`hecate generate workflow docs-pages` once the CLI exists.

## Releases

The `release.yml` workflow builds the `hecate` executable and attaches it to a GitHub Release (owner requirements of
2026-11-25). Rocks, Docker images and the installers come later (P3).

- **Names.** A tag and its release are named `<version>-<revision>` in LuaRocks form, without a `v` prefix (`0.1.0-1`).
  The version is `X.Y.Z`, optionally followed directly by a pre-release: `alpha`, `beta`, `rc` or `pre` and a number
  (`0.4.2rc1-1`, `1.0.0beta2-1`), the tokens that LuaRocks orders before the final release (`luarocks.core.vers`: alpha <
  beta < pre < rc < final; the order is informational here). `dev`, `scm` and `cvs` are refused, as are a hyphen before
  the pre-release (`0.4.2-rc1-1`), a pre-release without a number (`0.4.2rc-1`) and a missing revision. The grammar is
  `^[0-9]+\.[0-9]+\.[0-9]+((alpha|beta|rc|pre)[0-9]+)?-[0-9]+$`, one validator per language
  (`tools/lib/release_version.lua`, and the same expression in the setup action, a test keeps them equal).
  `X.Y.Z[pre]` must equal the root `VERSION` file, so a pre-release is built from a `VERSION` that holds `0.4.2rc1`
  (the rockspecs and the `version` fields follow it): the first job of the workflow (`package-cli --check-tag`) fails
  before anything is built when it does not. A version with a pre-release part is created as a draft **marked
  pre-release** (`gh release create --prerelease`; the `plan` job passes `package-cli --check-tag --prerelease`, which
  prints `true` or `false`, as the output `prerelease`).
- **Draft first, the owner publishes.** The owner enables GitHub's immutable releases setting: once a release is
  published, assets cannot be added. The workflow therefore runs on the **push of the tag**, builds on every platform,
  and creates the release as a **draft** with every asset attached (`gh release create <tag> --draft --verify-tag`),
  then stops. It never publishes: the owner reviews the draft (the assets, their `.sha256`, the notes, which point to
  `CHANGELOG.md`) and publishes it by hand. (`release: created` is not fired for a draft and `published` is too late for
  assets, hence the tag trigger.)
- **Assets**, per platform: `hecate-<version>-<os>-<arch>.tar.gz` (`.zip` on Windows) and
  `hecate-<version>-<os>-<arch>.tar.gz.sha256` (`<hex>  <archive name>`, the `sha256sum` format; `.zip.sha256` on
  Windows); `os` is `linux`, `darwin` or `windows`, `arch` is `x86_64` or `aarch64`, `<version>` is the whole `X.Y.Z[pre]-R`.
  The executable is at the root of the archive: `hecate`, or `hecate.exe` with `lua55.dll` beside it on Windows. These are
  the names that the setup action (`packages/actions/setup`) downloads. The archive is deterministic (`package-cli`:
  sorted entries, fixed time and owner; the Windows zip holds stored entries). On a tag, each archive also gets a build
  provenance attestation (`actions/attest-build-provenance`; `gh attestation verify <archive> --repo <owner/repo>`).
- **Platforms** for now: the three that `ci.yml` builds and tests (`ubuntu-latest` gives linux-x86_64, `macos-latest`
  darwin-aarch64, `windows-latest` windows-x86_64; os and architecture come from `uname` or the Windows environment,
  not from a table). aarch64 Linux and Windows are to be added to the matrix when runners are chosen for them; the six
  targets planned for the P3 release (automation.md) include them.
- **Same build as CI.** The toolchain steps are those of `ci.yml` (same pins and cache key), then
  `build-cli --strict`, `package-cli` and its smoke test: the archive is extracted and `hecate version` must print the
  expected `X.Y.Z[pre]` (the content of `VERSION`).
- **Rehearsal.** A pull request that touches the release machinery (`release.yml`, `package-cli`, `build-cli`, the archive
  library, the C host) and `workflow_dispatch` (input `revision`, default `1`) run the same plan, build, packaging and
  smoke test on the matrix, keep the archives as workflow artifacts (seven days) and create no release. The pull request
  trigger is how a change to the release is tested before it is merged: GitHub lists a dispatchable workflow only once
  the file is on the default branch (the same holds for `gh workflow run release.yml --ref <branch>`).
- **Permissions.** Every job has `contents: read`; the build jobs add `id-token` and `attestations: write` for the
  attestation; only `draft-release` has `contents: write`.

## Delivery to a server

Without Docker, a release is a folder that a server can run (owner agreement of 2026-11-24; `hecate package` and
`hecate generate systemd` exist). The usual path, which the commands are to support:

1. CI builds the release on the OS and architecture of the server: `hecate install --frozen`, then `hecate package`,
   an archive `<name>-<version>-<os>-<arch>.tar.gz` (a `.zip` on Windows) with `hecate.project.lua`, `hecate.lock`,
   `main.lua`, `src/`, `config/` (the layers, never secrets) and `lua_modules/`, a `RELEASE` file (project version,
   Hecate version, Lua release, platform) and a `.sha256` next to it. Tests, `.git`, `.hecate/` and `docs/dist` stay out.
2. The server has the `hecate` executable and a unit made by `hecate generate systemd`; secrets and the environment
   come from an `EnvironmentFile` outside the release (`HECATE_*`, `HECATE_ENV=production`).
3. A deploy unpacks the archive in a new directory, checks the checksum, switches a `current` symbolic link and runs
   `systemctl reload` (SIGHUP, ADR 0023) or a restart; a rollback switches the link back. TLS and the public port are a
   reverse proxy's (Caddy, nginx) in front of `hecate serve`.

## Templates

`api` (default: controllers, schemas, tests; `--ci github` also generates
the `ci` workflow; `contract` and `docs-pages` are separate kinds), `minimal` (single route
module), `crud` (PostgreSQL, ORM, migrations). Templates live in
`packages/cli/templates/` and are tested in CI by generating and testing a project.
