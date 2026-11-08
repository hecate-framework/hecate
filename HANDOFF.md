<!-- Relay handoff note. Lives only on relay branches; deleted before review. -->
# Handoff

- roadmap_item: `config`: layered configuration validated by schemas; write its specification section in `docs/architecture/`, including the logging keys (OQ-62) and the `limits.max_depth` key that lowers the nesting depth of `json` and `schema` together (OQ-92).
- status: in-progress
- lock_until: 2026-11-08T23:00:00Z
- last_update: 2026-11-08T21:50:00Z

## Done

- Claimed (cd407f7). `container` is complete in PR #152 awaiting owner review; independent of `config`.
- Spec `docs/architecture/configuration.md`, glossary, links (fc36e78).
- Tests and implementation, CHANGELOG (8e329e0).
- README, how-to page, tested example (f686433).
- Local: `test config`, `typecheck` ok.

## Next steps

1. Wait for CI on the three platforms (the `test tools` tcp-echo failure seen in the sandbox is probably environmental; check CI).
2. Run `/review-package config` (reviewers: architect, api-reviewer, terminology, test-engineer, security for secrets); triage findings.
3. Known wart: empty array is exposed as an empty `Section`, not a `List`; fix or record.
4. French mirror of the how-to is not written (check whether CI requires it).
5. When green and reviewed: delete HANDOFF.md, tick the roadmap item, mark PR ready, ask the owner for review.

## Decisions taken (and where they are recorded)

- Conservative choices of the spec: OQ-101 (docs/open-questions.md). Mirror issue to open.
- `limits.max_depth` is validated but has no effect until `kernel` adds a lowering-only setter to json/schema.

## Doubts and questions for the owner

- OQ-101.

## Commands to re-run

```sh
lua tools/run.lua setup-luals   # once per session: pinned LuaLS into spikes/luals
lua tools/run.lua typecheck     # required before every push (CI fails on any warning)
lua tools/run.lua test config
```
