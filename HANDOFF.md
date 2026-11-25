<!-- Relay handoff note. Lives only on relay branches; deleted before review. -->
# Handoff

- roadmap_item: Docker images (runtime and build variants, amd64 + arm64). Also (OQ-135): a compose stack showing the contract rendered.
- status: in-progress
- lock_until: 2026-11-25T23:10:00Z
- last_update: 2026-11-25T21:45:00Z

## Done

- Claimed the item (branch `claude/relay-docker-images`). Open PRs #231 (cli v1) and #236 (meta-rock) are finished and wait for owner review, so this run takes the next item.

## Next steps

1. Read `docs/architecture/versioning-and-distribution.md#docker-images`, `docker/README.md`, ADR 0024 (CA certificates), `tools/bootstrap/bootstrap.sh` (pinned Lua 5.5.1 and LuaRocks, reusable by the images).
2. `docker/runtime/Dockerfile` and `docker/build/Dockerfile` (debian and alpine variants, non-root user, OCI labels incl. `org.hecate.lua-version`), `docker/bake.hcl`.
3. A task or check that the images carry CA certificates and the labels (tests first).
4. `docker.yml` (amd64 + arm64, Trivy scan, weekly rebuild), `docker/README.md`, website how-to with the compose stack (OQ-135, images pinned), CHANGELOG, roadmap tick.

## Decisions taken (and where they are recorded)

## Doubts and questions for the owner

## Commands to re-run

```sh
lua tools/run.lua setup-luals   # once per session: pinned LuaLS into spikes/luals
lua tools/run.lua typecheck     # required before every push (CI fails on any warning)
```
