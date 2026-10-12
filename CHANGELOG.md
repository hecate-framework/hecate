# Changelog

All notable changes are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses
[Semantic Versioning](https://semver.org/) with lockstep versions across all packages
(see [ADR 0005](docs/adr/0005-single-brand-monorepo-lockstep-versioning.md)).

Each release heading states the supported Lua version.

## [Unreleased] — Lua 5.5

### Added

- `hecate.core` (Phase 1): `class`, `trait`, `interface`, `finalise` (single inheritance, flat trait composition with exclusion and aliasing, conformance checked at finalisation, inherited metamethods including `__close`), introspection (`name`, `superclass`, `traits`, `interfaces`, `is_instance_of`, `implements`, `origin`), the `Error` hierarchy with cause chaining, stable codes and optional tracebacks, `enumeration`, `value_class` and `hecate.core.compat`. Open points: OQ-19 to OQ-21.
- Monorepo tooling: task runner `tools/run.lua` (`check-package-structure`, `check-versions`, `check-rockspecs`, `gen-rockspecs`, `lint`, `typecheck`, `test`, `format`/`format-check` as no-ops), bootstrap test harness `tools/harness/` (ADR 0008), `.luarc.json`, per-package `scm-1` rockspecs and `tests/` skeletons.
- `check-adr-index`, `check-links`, `check-changelog`, `check-boundaries`, `check-glossary` and `check-lua-constructs` tasks; `affected` and `matrix` tasks (`--json` carries the data); `gen-catalogue`, `gen-dependency-graph` and `gen-llms-txt` (package list; `--check` verifies); `new-package`.
- CI workflow `ci.yml`: Ubuntu, macOS and Windows with Lua 5.5, cached toolchain bootstrap, pinned LuaLS, C toolchain check, and the Phase 0 quality tasks.
- Git hooks: `lua tools/hooks/install.lua` installs `pre-commit` (lint of staged package sources) and `commit-msg` (Conventional Commits) shims; `lib/commitmsg.lua` holds the validation.
- `ci.yml` plans with the `affected` task: lint and tests run only for packages affected by the diff (reverse dependencies included).
- OQ-3 decision: the repository uses no formatter until one fully supports Lua 5.5.
- Specification workspace: vision, architecture, decision records, roadmap.
- Spike reports OQ-4, OQ-5, OQ-6 and ADRs 0019 (llhttp), 0020 (yyjson decoder, serde_json encoder), 0021 (Rust as a build-time tool for native modules; rustls).
- `tools/bootstrap/bootstrap.sh` and `bootstrap.ps1`: pinned Lua 5.5.1 and LuaRocks 3.13.0 bootstrap with SHA-256 verification for Linux, macOS and Windows (x64 and arm64); `tools/cloud/setup.sh` pins the bootstrap by commit and checksum.
- Contributor bootstrap: `tools/bootstrap/bootstrap.sh --prefix .hecate/toolchain` installs the pinned toolchain inside the repository; relative prefixes are resolved before the build.
