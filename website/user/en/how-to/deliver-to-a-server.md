---
description: Deliver a hecate application to a server without Docker - a release archive, a systemd unit, a symbolic link to switch versions and a reverse proxy for TLS.
hecate: "0.x"
lua: "5.5"
order: 6
---

# Deliver to a server

This guide delivers a project to a Linux server without a container. It is written for hecate 0.x and Lua 5.5. The
server needs the `hecate` executable and nothing else.

## Build the release

Build on the operating system and architecture of the server (the dependencies with C code are compiled for it), in CI:

```sh
hecate install --frozen
hecate package
```

`hecate package` writes `shop-0.1.0-linux-x86_64.tar.gz` and `shop-0.1.0-linux-x86_64.tar.gz.sha256`: the manifest, the
lock, `main.lua`, `src`, `config` and `lua_modules`, plus a `RELEASE` file with the versions. Tests, `.git`, `.hecate` and
the documentation site are not in it. Keep secrets out of the project: they come from the environment of the server.

## Run the checks in CI

`hecate generate workflow ci` writes `.github/workflows/ci.yml` (`hecate new shop --ci github` does it for a new project):
on every push and pull request, on Linux, macOS and Windows, it installs the executable with the setup action
`hecate-framework/hecate-actions/setup`, then runs `hecate install --frozen`, `hecate test` and, for a project with a contract,
`hecate contract export` and `hecate contract lint`. Add `--doc` to build the documentation too. The workflow calls only
`hecate` commands, so a run behaves like a local one; the `version` it passes to the action is the release of Hecate, `X.Y.Z-R` (`0.4.0-1`, no `v`; a pre-release is written directly after `X.Y.Z`: `0.4.2rc1-1`). Regenerate it with `--force` after an upgrade of Hecate: the command prints the diff of the file first. To build
and package the release on the server's platform, add a job that runs `hecate install --frozen` and `hecate package`.

Two more workflows: `hecate generate workflow contract` writes `.github/workflows/contract.yml`, which on every pull request
runs `hecate contract diff origin/<base branch>` and fails on a breaking change of the contract (commit `openapi.json` on
the base branch first, with `hecate contract export --output openapi.json`); `hecate generate workflow docs-pages` writes
`.github/workflows/docs.yml`, which on a push to the default branch builds the documentation with `hecate doc build --yes`
and publishes it to GitHub Pages (set the source of Pages to "GitHub Actions"). A `release` workflow is not generated yet.

## Prepare the server

```sh
hecate generate systemd --user shop --executable /usr/local/bin/hecate --output shop.service
```

Edit the unit if you need to, copy it to `/etc/systemd/system/shop.service` and make a file for the settings and secrets,
`/etc/shop/env`, with `HECATE_*` variables (`HECATE_ENV=production`, the database password, and so on); add
`EnvironmentFile=/etc/shop/env` to the unit. Then `systemctl daemon-reload && systemctl enable shop`.

## Deploy

Each release goes into its own directory, and a link says which one runs:

```sh
sha256sum -c shop-0.1.0-linux-x86_64.tar.gz.sha256
mkdir /srv/shop/releases/0.1.0 && tar -xzf shop-0.1.0-linux-x86_64.tar.gz -C /srv/shop/releases/0.1.0
ln -sfn /srv/shop/releases/0.1.0 /srv/shop/current
systemctl reload shop
```

The unit's working directory is the `current` link. `systemctl reload` sends `SIGHUP`, which replaces the workers of a
[multi-process](multi-process-deployment.md) application one at a time, with no downtime (a restart is `systemctl restart
shop`). To roll back, point the link at the previous release and reload.

## Put a reverse proxy in front

`hecate serve` listens on the loopback interface. Let a reverse proxy such as Caddy or nginx own the public port and TLS,
and pass requests to `127.0.0.1:8080`. The [checklist](before-going-to-production.md) lists what to verify before the first
deployment.
