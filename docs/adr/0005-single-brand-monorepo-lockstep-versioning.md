# 0005 — One brand, functional package names, monorepo, lockstep versions

- **Status:** Accepted
- **Date:** 2026-10-11
- **Deciders:** project owner
- **Packages:** all
- **Related:** [overview.md](../architecture/overview.md), [versioning-and-distribution.md](../architecture/versioning-and-distribution.md)

## Context

The ecosystem must feel like one framework, not like libraries glued together. The
owner keeps "Hecate" as the brand (like Symfony, the name does not describe the
function) but wants components named after what they do.

## Decision

- Brand: **Hecate**. Packages are named by function: directory `packages/<name>`,
  rock `hecate-<name>`, module `hecate.<name>`. No per-package code names.
- One **monorepo** holds all packages, the website, Docker images, benchmarks and
  examples.
- **Lockstep versioning**: every package is released with the same version number at
  the same time. `hecate-orm 0.4.2` is always compatible with `hecate-http 0.4.2`.
- Meta-rock `hecate` depends on the standard edition (kernel, http, router, schema,
  openapi, container, config, log, json, reactor, net, core).

## Consequences

- Users reason about one version. Cross-package refactors are atomic.
- Some releases bump packages that did not change; acceptable.
- Release tooling must publish many rocks atomically (see automation.md, `release`).

## Verification

`check-versions` script: all rockspecs share the version in `VERSION`.
