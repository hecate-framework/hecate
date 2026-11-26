<!-- Relay handoff note. Lives only on relay branches; deleted before review. -->
# Handoff

- roadmap_item: Docker images (runtime and build variants, amd64 + arm64). Also (OQ-135): a compose stack showing the contract rendered.
- status: in-progress
- lock_until: 2026-11-26T14:50:00Z
- last_update: 2026-11-26T13:20:00Z

## Done

- Step 6 (9d93266): security and terminology reviews done and fixed (proxy published on 127.0.0.1 only, `.dockerignore`, nginx hardening, CORS wording). Residuals for the owner: digest pins before release; Trivy mounts docker.sock; `check-docker` could reject `curl | sh`, `ADD <url>` and secrets in ARGs (a later hardening).

- Step 5: CI of 0bfe7de fully green (all images, Trivy included). Compose stack of OQ-135 written: `docker/compose/{compose.yaml,nginx.conf}`, how-to `render-the-contract-with-docker-compose` (English; French mirror not written: the website item and `translator-fr` carry it), index, README, CHANGELOG.

- Step 4: CI of docker.yml ran: all images build; only Trivy on runtime/alpine failed (HIGH CVE-2026-124709 in libcrypto3/libssl3, fixed in 3.5.9-r2). Added `apk upgrade --no-cache` to the final stage of the alpine runtime and build Dockerfiles. Next CI run to confirm.

- Step 3: the `build/` rule of `.gitignore` had swallowed `docker/build/`, so check-docker failed in CI; added `!docker/build/` and recreated `docker/build/Dockerfile.{debian,alpine}` (runtime + compilers and headers). check-docker, typecheck ok locally.

- Step 2 (commit below): `docker/runtime` and `docker/build` Dockerfiles (debian, alpine), `docker/bake.hcl`, task `check-docker` (`tools/lib/dockerfile.lua`, `tools/tests/dockerfile_test.lua`), `docker.yml`, `ci.yml` runs `check-docker`, automation.md, docker/README.md, CHANGELOG. Typecheck, lint, check-changelog ok.

- Claimed the item (branch `claude/relay-docker-images`). Open PRs #231 (cli v1) and #236 (meta-rock) are finished and wait for owner review, so this run takes the next item.

## Next steps

1. PR #231 is merged (merge commit in this branch). Wait for CI of the merge on the three platforms and docker.yml. If green: the `hecate` executable is NOT added to the images (it needs the Rust toolchain or a published release, owner gate); record it as a follow-up roadmap item `Docker images: the hecate executable`, tick this item, delete HANDOFF.md, mark ready, ask for review.

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
