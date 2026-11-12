<!-- Relay handoff note. Lives only on relay branches; deleted before review. -->
# Handoff

- roadmap_item: Example: `examples/hello` (JSON API with validation).
- status: in-progress
- lock_until: 2026-11-12T05:13:32Z
- last_update: 2026-11-12T03:43:32Z

Stacked on the `kernel` pull request (#166, branch `claude/sweet-feynman-h1j6tu`), which is ready for review
but not merged: this pull request targets that branch until #166 is merged, then `main`.

## Done

## Next steps

1. Read the kernel README and specification, `examples/README.md`, the Phase 2 exit criterion; record what the
   Phase 2 example can and cannot show before Phase 3 (`hecate test`, `hecate contract lint`, OpenAPI do not exist yet).
2. Write the integration tests of the example (valid request, invalid input → RFC 9457 problem details, N workers,
   graceful shutdown drains in-flight requests), then the example itself.
3. Wire the example into CI on the three platforms.
4. Docs: example README, tutorial link on the website if any, `CHANGELOG.md`.

## Decisions taken (and where they are recorded)

## Doubts and questions for the owner

## Commands to re-run

```sh
lua tools/run.lua setup-luals   # once per session: pinned LuaLS into spikes/luals
lua tools/run.lua typecheck     # required before every push (CI fails on any warning)
```
