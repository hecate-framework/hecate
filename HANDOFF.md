<!-- Relay handoff note. Lives only on relay branches; deleted before review. -->
# Handoff

- roadmap_item: `config`: layered configuration validated by schemas; write its specification section in `docs/architecture/`, including the logging keys (OQ-62) and the `limits.max_depth` key that lowers the nesting depth of `json` and `schema` together (OQ-92).
- status: in-progress
- lock_until: 2026-11-09T02:20:12Z
- last_update: 2026-11-09T00:50:12Z

## Done

- Claimed (cd407f7). `container` is complete in PR #152 awaiting owner review; independent of `config`.
- Spec `docs/architecture/configuration.md`, glossary, links (fc36e78).
- Tests and implementation, CHANGELOG (8e329e0).
- README, how-to page, tested example (f686433).
- Local: `test config`, `typecheck` ok.
- Owner answers on OQ-101 applied (6d2292c): default environment is `production`, OQ-101 resolved, kernel handoffs added to the roadmap. No lock is held (owner request): the next relay run may resume.
- Website build failed on the how-to's out-of-root link; replaced by the GitHub URL (this commit). `check-links`, `typecheck` ok.

- Review (architect, pkg-config, api, terminology, test-engineer) done; fixes applied: boolean false override, empty array as List, single violation per coercion failure, secret redaction in errors, BOM/directory file reading, reserved env names, `secret` option renamed `wrap_secret`, dotted violation paths with hint, glossary and doc terms. typecheck and test config ok (this commit).

## Next steps

1. Wait for CI on the three platforms for the review-fix commit.
2. Triage deferred review items: cross-key `logging.file.path` rule skipped when build fails; `describe()` `%q` escaping; property-based tests; lone-CR and empty secret file semantics; `HECATE_ENV=""`; Windows empty-env test; French mirror of the how-to (check whether CI requires it). Record them as known limitations in `docs/open-questions.md` (or roadmap items) with a mirror issue.
3. When green: delete HANDOFF.md, tick the roadmap item, mark PR ready, ask the owner for review.

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
