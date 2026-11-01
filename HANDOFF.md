<!-- Relay handoff note. Lives only on relay branches; deleted before review. -->
# Handoff

- roadmap_item: **Phase 1 gate**: verification of the phase, as described in Phase gates. Open questions to put to the owner before Phase 2: OQ-50, OQ-47, OQ-23, OQ-24, OQ-26 (1) and OQ-22.
- status: in-progress
- lock_until: 2026-11-01T11:56:51Z
- last_update: 2026-11-01T10:26:51Z

## Done

- Claimed the gate (PR #40 merged, benchmarks item ticked).
- Ran all check tasks, build-native json/doc, full test, bench tcp-echo: all ok. Wrote docs/reviews/phase-1.md (coherence pending).
- Cloud tip: run `eval "$(luarocks path)"` before `test`, else luv is not found.

## Next steps

Run 10 (2026-11-01, owner said "please go on"): `net` follow-up in progress, one commit per part, all on this branch. CI was green on 7ede638 (3 platforms) for the reactor follow-up. `net` parts: [x] handshake defaults (accept 60 s, connect 10 s; `handshake_timeout` already editable and `max_message` already editable: nothing to change for it). [x] `BufferedWriter:close` flushes under `reactor.shield` with the new writer option `close_timeout`, default 5 s: NOT decided by the owner, recorded as a proposal in OQ-29 (5) and networking.md: mention it in the final comment on the PR (owner to confirm). [x] Unix socket bound in a private `0700` directory then linked (reactor/pipe.lua; macOS and Windows CI to confirm: `fs_link` of a socket, `path()` semantics). Cleanup at the end of the item: remove the struck-through entry 2 in the "Decided, not yet implemented" list of networking.md once all parts are done. [x] `net.listen` binds every resolved address (one reactor listener per address, same port; skip EAFNOSUPPORT/EADDRNOTAVAIL when another is bound: a conservative tolerance NOT in the owner decision, recorded in OQ-32 (3) and networking.md for confirmation: mention it in the final comment; tests use ::1 else 127.0.0.2, locally only 127.0.0.2 works, CI macOS/Windows must confirm). [x] CRL option `client_crl_pem` on `tls.server_config` (PEM string, needs client_ca_pem, end-entity only, no refresh, expiry not enforced: a conservative FORM not decided by the owner, recorded in OQ-47 (6) and networking.md: mention it in the final comment; new fixtures revocation_ca/valid_client/revoked_client/revoked.crl in packages/net/tests/fixtures, CA key discarded). [x] Happy Eyeballs in `net.connect` (tests/unit/happy_eyeballs_test.lua, virtual clock; resolver order kept, no family interleaving, delay not an option). Remaining: [ ] writer-capacity benchmark vs Go bufio 4 KiB (benchmarks/; see how `net/buffered-writer` micro-benchmark works and extend it); then the cleanup of the "Decided, not yet implemented" list in networking.md (item 5 only left), tick the roadmap item, run the checks, check CI. Then tick the `net` follow-up item, then the gate run. Re-run: `eval "$(luarocks path)"; lua tools/run.lua build-native net; lua tools/run.lua test net`.

Run 9 (2026-11-01, owner asked: no stacked branches, work directly on this branch): the `reactor` follow-up roadmap item is DONE and ticked (`core.IoError`, `on_unobserved_failure`, `reactor.shield(limit, fn, ...)` with a required limit; docs, README, CHANGELOG, OQ-23 note, website how-to). `BufferedWriter:close` flushing under the shield moved into the `net` follow-up item (choose its shield deadline and record it). The French how-to `website/fr/how-to/deadlines-and-cancellation.md` lacks the new section (stale stamp, A44/B32 deferral). Check CI of this branch on the three platforms next (not yet checked for the new commits). Next run: the `net` follow-up item (one item per run), then the gate run (CI check, tick the gate, delete this file, ready for review). PR #51 (stacked) is closed; branch `claude/relay-reactor-shield` can be deleted.

Update 2026-11-01 (owner conversation): the owner HAS decided every item run 8 calls pending (OQ-50 presence set, OQ-26 (4) keep refusing, A33, A40, A41, A42, C03, C17, C18, ambient glossary); they are recorded in docs/open-questions.md and docs/reviews/phase-1-owner-decisions.md. Do not ask for them again; issue 48 is corrected. What remains: (1) the deferred minors of docs/reviews/phase-1-review-package.md need the owner's call; (2) the two roadmap items before the gate (`reactor` follow-up, `net` follow-up incl. Happy Eyeballs) are decided but NOT implemented: take them next, one per run, each on its own branch; (3) then the gate run ticks the gate and deletes this file.

Run 8 (2026-10-28): CI green on 3 platforms at 042d27f; issue 48 updated. Nothing left for the relay: waiting for owner decisions, then tick the gate and delete this file. Lock released.

Run 7 (2026-10-28): minors net TlsStream:write check and log redact annotation fixed (net tests ok with HECATE_REQUIRE_TLS=1). Remaining: check CI of the PR on 3 platforms, update issue 48 with the review findings left (other minors deferred), tick the gate only after owner decisions. Lock released.

Run 6 (2026-10-28): the four majors R1, L1, L2, D1 are fixed test-first (commits on this branch; reactor, log, doc tests ok). Remaining: cheap minors (net TlsStream:write check, log annotations), then CI check on 3 platforms, update issue 48, tick the gate only after owner decisions. Lock released.

Run 5 (2026-10-28): CI green on 3 platforms (run 40603502783). Review agents done: findings in docs/reviews/phase-1-review-package.md. Next: fix the four majors R1 (reactor deadline inf), L1 (FileSink flush), L2 (Logger option checks), D1 (doc javascript: action links), each test-first (`eval "$(luarocks path)"`, build-native json/doc first), then the cheap minors (net TlsStream:write check, log annotations); the rest may become roadmap items or be deferred with the owner; then update issue 48 and tick the gate. Lock released.

Step done 2026-10-27 (run 4, end): parts merged into docs/reviews/phase-1-coherence-findings.md (raw parts deleted), phase-1.md section 3 and verdict updated. Remaining: (1) `/review-package` on core, reactor, net, json, log, doc and a note of their findings in phase-1.md; (2) check CI of this PR on the 3 platforms; (3) update the needs-decision issue with the D items listed at the top of the coherence report; (4) tick the gate only after the owner decides or defers them. Lock released.

Step done 2026-10-27 (run 4, later): Part C small findings fixed (C01, C02, C04-C12, C15, C16, C19, C20, C23-C27; C13/C14 already in order). Not fixed: C03, C17, C18 (D, owner), C21 (roadmap restructuring, M), C22 (README phase of doc, left as is with a status note), the glossary entry for ambient context (owner), French stamps of 7 pages not compared. Next: merge the three raw parts into docs/reviews/phase-1-coherence-findings.md, update phase-1.md section 3 (fixed / left), delete _phase-1-part-*.md, run /review-package, put the owner items in open-questions and the needs-decision issue, tick the gate only when decided.

Step done 2026-10-27 (run 4): Part B finished: all small findings fixed (B18 was already in order; B32: stamps bumped for the five pages compared in scope, the 7 other French pages not compared: left for the A44/B32 deferral). Next: Part C small findings (docs/reviews/_phase-1-part-C.md, skip D items), then merge parts into phase-1-coherence-findings.md, phase-1.md section 3, /review-package, tick the gate. Re-run: `eval "$(luarocks path)"`; `lua tools/run.lua build-native json` and `doc` before tests.

Step done 2026-10-27 (run 3): Part B partly fixed: B08-B11, B14 (README, CHANGELOG, how-to), B12, B17, B21, B26 (workflow loop; the reference index already had log), B27, B28, B29 (done in docs and sources). Remaining part B: B01-B07, B13, B15, B16, B18-B20, B22-B25, B30-B32. Then Part C, merge parts, phase-1.md section 3, /review-package. Note: run `lua tools/run.lua build-native json` before testing log, else json-dependent tests fail.

Step done 2026-10-27 (run 2): Part A small findings fixed (all S except A02, A44 skipped; A29, A33, A40, A41, A42 are owner items). A02 (~30 core error messages: convert to qualified prefix or state exception in coding-standards.md) and A44 (French source_revision bump after checking each page) left. Next: same for Part B, then Part C (agent: general-purpose, give it the part file, skip D items, no commit), then merge parts into phase-1-coherence-findings.md, update phase-1.md section 3, run /review-package. Re-run: `eval "$(luarocks path)"` before `lua tools/run.lua test <pkg>`.

Owner answered OQ-50/47/23/24/26/22 on 2026-10-27 (recorded in docs/open-questions.md). Open: OQ-50 presence set vs json.null, OQ-26 (4) virtual clock. Roadmap items for those answers added before the gate (reactor follow-up, net follow-up). Next: the coherence fixes (small findings of parts A, B, C); the seven D findings and the ambient-context glossary entry still await the owner.

Coherence audit done in three raw parts (docs/reviews/_phase-1-part-{A,B,C}.md: 45+32+27 findings). Next: owner answers on the D items and the six OQs; then fix the small findings in this PR, merge the parts into phase-1-coherence-findings.md, update phase-1.md section 3, run /review-package. DONE earlier: sections 1, 2, 4 of docs/reviews/phase-1.md. Remaining: section 3 coherence audit (file by file, as phase-0-coherence-findings.md) and /review-package on core, reactor, net, json, log, doc; then owner decisions on OQ-50/47/23/24/26/22 (issue opened); then tick the gate and delete this file.

- Completeness: read every ticked Phase 1 item against its spec and the definition of done.
- It works: run the check catalogue, native builds, tests, examples, benchmarks; read CI of latest main.
- Coherence: docs, ADRs, README, website en/fr, llms.txt.
- Write docs/reviews/phase-1.md; update docs/open-questions.md; open/update needs-decision issue.

## Decisions taken (and where they are recorded)

## Doubts and questions for the owner

## Commands to re-run

```sh
```
