<!-- Relay handoff note. Lives only on relay branches; deleted before review. -->
# Handoff

- roadmap_item: Website skeleton in `website/en` with the Hecate visual identity (docs for `net` and the new reactor primitives owed)
- status: in-progress
- lock_until: 2026-10-19T00:03:23Z
- last_update: 2026-10-18T22:33:23Z

## Done

- Claimed the item (draft PR #21).
- Five how-to guides in website/en/how-to/ (TCP, TLS, deadlines, UDP and pipes, child processes), OUTLINE.md and llms.txt entries. check-links, check-glossary, build --strict pass.

## Next steps

1. Explanations: transport model, back-pressure and half-close, TLS trust and ADR 0024 defaults, multi-process serving (ADR 0023).
2. Sync website/en/reference/glossary.md with docs/glossary.md (missing: stream, back-pressure, half-close, spawn, message pipe, primary, worker, listening strategy).
3. Tested examples for spawn, ipc, deadlines, pipes (packages/reactor/examples/) so guides can point to them; luv is not installed in the cloud env.
4. Generated reference pages need lua-language-server (not installed here); core/reactor/net reference check in CI.
5. French pages with translator-fr; then delete this file, tick the roadmap item, mark ready.

## Decisions taken (and where they are recorded)

None.

## Doubts and questions for the owner

- Untested snippets in the guides (see step 3); ADR/example links use blob/main and resolve only after merge.

## Commands to re-run

```sh
lua tools/run.lua check-links
lua tools/run.lua check-glossary
lua packages/doc/bin/build.lua website --strict
```
