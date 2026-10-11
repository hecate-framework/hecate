# Changelog

All notable changes are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses
[Semantic Versioning](https://semver.org/) with lockstep versions across all packages
(see [ADR 0005](docs/adr/0005-single-brand-monorepo-lockstep-versioning.md)).

Each release heading states the supported Lua version.

## [Unreleased] — Lua 5.5

### Added

- Specification workspace: vision, architecture, decision records, roadmap.
- Spike reports OQ-4, OQ-5, OQ-6 and ADRs 0019 (llhttp), 0020 (yyjson decoder, serde_json encoder), 0021 (Rust as a build-time tool for native modules; rustls).
- `tools/bootstrap/bootstrap.sh`: pinned Lua 5.5.1 and LuaRocks 3.13.0 bootstrap with SHA-256 verification; `tools/cloud/setup.sh` now delegates to it.
