# Docker images

Specification: [docs/architecture/versioning-and-distribution.md](../docs/architecture/versioning-and-distribution.md#docker-images).
Built from Phase 3 by `docker.yml`.

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
- Secure: non-root user, Trivy scan in CI, weekly rebuild.
- Labelled: OCI labels including `org.hecate.lua-version`.

Planned layout: `docker/runtime/Dockerfile`, `docker/build/Dockerfile`,
`docker/dev/Dockerfile`, `docker/bake.hcl` (buildx bake matrix).
