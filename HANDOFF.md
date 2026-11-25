<!-- Relay handoff note. Lives only on relay branches; deleted before review. -->
# Handoff

- roadmap_item: Docker images (runtime and build variants, amd64 + arm64). Also (OQ-135): a compose stack showing the contract rendered.
- status: in-progress
- lock_until: 2026-11-25T23:50:00Z
- last_update: 2026-11-25T22:20:00Z

## Done

- Step 2 (commit below): `docker/runtime` and `docker/build` Dockerfiles (debian, alpine), `docker/bake.hcl`, task `check-docker` (`tools/lib/dockerfile.lua`, `tools/tests/dockerfile_test.lua`), `docker.yml`, `ci.yml` runs `check-docker`, automation.md, docker/README.md, CHANGELOG. Typecheck, lint, check-changelog ok.

- Claimed the item (branch `claude/relay-docker-images`). Open PRs #231 (cli v1) and #236 (meta-rock) are finished and wait for owner review, so this run takes the next item.

## Next steps

1. Check the first CI run of `docker.yml` on this pull request (nobody could run a Docker daemon in the cloud session; the Dockerfiles, bake matrix, smoke test and Trivy step are untested). Fix what fails (alpine `bash`/readline for `bootstrap.sh`, `libuv1`/`libssl3` package names, bake `matrix` naming, Trivy tag).
2. The `hecate` executable in `hecate/build` (build argument, after cli v1, PR #231); `hecate/dev` is out of this item.
3. The compose stack of OQ-135 (application, reverse proxy with one origin, Swagger UI reading `/openapi.json`, images pinned by tag or digest) as a website how-to in `website/user/en/how-to/` (+ French mirror note), tested example under `examples/` if the rules require it.
4. Terminology and security review of the Docker files (`/review-package` agents: ci-engineer, security-reviewer, cross-platform-reviewer), then tick the roadmap item, delete HANDOFF.md, mark ready.

## Decisions taken (and where they are recorded)

- No new third-party GitHub action: buildx via the runner's Docker, Trivy from its container image `aquasec/trivy:0.58.2` (conservative; the SHA pins of actions cannot be verified offline). To confirm by the owner.
- Base tags `debian:bookworm-slim` and `alpine:3.22` (tags, not digests; digests to pin at release).

## Doubts and questions for the owner

- The Docker build was not run here (no daemon); `lua tools/run.lua test tools` shows the BenchmarkScenarioTest failures without `eval "$(luarocks path)"`, unrelated.

## Commands to re-run

```sh
lua tools/run.lua setup-luals   # once per session: pinned LuaLS into spikes/luals
lua tools/run.lua typecheck     # required before every push (CI fails on any warning)
```
