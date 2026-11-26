# Docker images

Specification: [docs/architecture/versioning-and-distribution.md](../docs/architecture/versioning-and-distribution.md#docker-images).
Built from Phase 3 by `docker.yml`. **Status:** `runtime` and `build` (debian, alpine) are written, checked by `lua tools/run.lua check-docker` and built by `docker.yml`; `dev` and the `hecate` executable in `build` come later.

| Image | Purpose | Base variants |
|---|---|---|
| `hecate/runtime` | run applications: Lua 5.5, LuaRocks, libuv, OpenSSL, CA certificates, non-root user | `debian` (slim, default), `alpine` |
| `hecate/build` | build stage: runtime + compilers, headers, `hecate` CLI | `debian`, `alpine` |
| `hecate/dev` | dev containers: build + LuaLS, formatter, debugging tools | `debian` |

Tags: `<version>-lua<lua line>-<variant>` (e.g. `0.3.0-lua5.5-debian`), `<major.minor>`,
`latest` → debian. Architectures: `linux/amd64`, `linux/arm64`.

Requirements:

- Reproducible: Lua and LuaRocks downloaded with pinned versions and verified checksums.
- Small: runtime image without compilers; multi-stage builds in the generated
  Dockerfile (`hecate docker init`).
- Out-of-the-box TLS: the runtime and build images install the system CA certificates, because the default trust store of `net` is the operating system's ([ADR 0024](../docs/adr/0024-tls-trust-store.md)); a release check fails otherwise.
- Secure: non-root user, Trivy scan in CI, weekly rebuild.
- Labelled: OCI labels including `org.hecate.lua-version`.

Layout: `docker/<image>/Dockerfile.<variant>` (`runtime`, `build`; `dev` planned) and `docker/bake.hcl` (buildx bake
matrix). Build from the repository root: `docker buildx bake -f docker/bake.hcl runtime-debian`.

Compose stack (OQ-135): `docker/compose/` shows the contract rendered (application, reverse proxy for one origin, Swagger UI); see the how-to `render-the-contract-with-docker-compose`.
