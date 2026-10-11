<!-- Relay handoff note. Lives only on relay branches; deleted before review. -->
# Handoff

- roadmap_item: Spikes OQ-4 (TLS), OQ-5 (JSON), OQ-6 (HTTP/1.1 parser)
- status: waiting-owner            <!-- in-progress | waiting-ci | waiting-owner -->
- lock_until: 2026-10-11T20:11:53Z
- last_update: 2026-10-11T18:42:22Z

## Done

- Claimed the item; draft PR #7 opened (labels relay, area:docs).
- Cloned llhttp into spikes/OQ-6/llhttp (shallow).

## Next steps

0. Resolve the denial above (one command per call, no cd chains).
1. Spike OQ-6 (llhttp vs Lua parser), then OQ-5, then OQ-4; one report each in docs/spikes/.

## Decisions taken (and where they are recorded)

## Doubts and questions for the owner

- DENIED by the auto-mode classifier (reason: Code from External): `cd spikes/OQ-6/llhttp && npm ci --silent; npm run build` (installing npm deps and running the llhttp build script to generate its C sources). Not retried. Owner: allow `npm ci` / `npm run build` under `spikes/OQ-6/llhttp`, or alternatively use the llhttp release tarball (pre-generated C), if the network allowlist permits.

## Commands to re-run

```sh
```
