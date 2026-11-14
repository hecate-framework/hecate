<!-- Relay handoff note. Lives only on relay branches; deleted before review. -->
# Handoff

- roadmap_item: `openapi`: OpenAPI 3.1 assembly, served endpoint, export, contract diff.
- status: in-progress            <!-- in-progress | waiting-ci | waiting-owner -->
<!-- Optional, only when the owner holds this pull request for one run: - owner: session `<session id>`, why. -->
- lock_until: 2026-11-14T16:00:47Z
- last_update: 2026-11-14T14:30:47Z

## Done

- Step 1: assembly core (`openapi.build`, `encode`, components, problem details), 15 unit tests, golden file, README, CHANGELOG (e1897bb).
- CI fix: OQ-129 row moved to the open table, `gen-catalogue` refreshed.
- Step 2: contract diff `openapi.diff` (36 tests, choices in OQ-129 (11)) (ca6cb9d).
- Owner answers on OQ-129 recorded (OQ-129 row, roadmap).
- Kernel: route `name` mandatory, no default name (8458973). Kernel integration tests that need native modules could not run in the sandbox: CI decides.
- Core: `hecate.core.status` table, `core.status.is_error`, and `core.Problem` as a marker interface with no member (owner decisions of 2026-11-14: interfaces declare no field; status 400..599; empty title accepted) (693bdca, 8abfbd3).
- Kernel: base `Problem` implements `core.Problem` with default 500 "Internal Server Error"; route flag `content_optional` (cf3c586, 7c37851); `http.Status` is an alias of `core.status` (5eb85af). CI green on the three platforms at that point.
- Step 3 `openapi`: `core.status`, problems recognised by `core.Problem`, mandatory names, `content_optional`, ordered `tags` and `external_docs`, `{rest}` documented (ca7ac03).
- Awaiting owner: OQ-129 (11) diff rules, `content_optional` name and empty-body rule, (13); then move OQ-129 to Resolved and close #199.
- Diff reports default, description, summary, example, tags, deprecated, security changes (cece774); `content_optional` permanent, accepts an empty body even with a Content-Type (bacfae8); owner answers recorded in OQ-129.
- Step 4 `openapi`: conformance test: structural self-check `tests/support/structure.lua` plus comparison with the pinned official schema (`oas/3.1/schema/2026-11-05` of OAI/spec.openapis.org, `fetch-fixtures openapi`, added to ci.yml and nightly.yml); a full validation is OQ-130 (issue #203).

## Next steps

1. Served `/openapi.json` (development default) and reference page; needs a kernel hook.
2. YAML output and the `hecate contract export` hook (kernel/cli).
3. Lint: names, descriptions, examples, undocumented responses as errors, unused listed tags.
4. Integration tests and website reference pages (`{rest...}` documented).
5. Later, optional: controller-level default `tags` (roadmap).
6. CI green on three platforms, delete HANDOFF.md, tick roadmap, mark ready.

## Decisions taken (and where they are recorded)

- OQ-129 (ten conservative choices, issue #199): operationId = route name, default response when none, security copied as declared, reason phrases duplicated.

## Doubts and questions for the owner

- Stray files `/before.txt` and `/after.txt` at the filesystem root of the sandbox (harmless; not in the repository).
- Never leave a git worktree under `.claude/worktrees/` while running `typecheck`: it duplicates every file (3571 warnings).

## Commands to re-run

```sh
lua tools/run.lua setup-luals   # once per session: pinned LuaLS into spikes/luals
lua tools/run.lua typecheck     # required before every push (CI fails on any warning)
```
