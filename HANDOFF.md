<!-- Relay handoff note. Lives only on relay branches; deleted before review. -->
# Handoff

- roadmap_item: `json` follow-up: remove the pure-Lua backend once it has no use (OQ-53)
- status: in-progress            <!-- in-progress | waiting-ci | waiting-owner -->
- lock_until: 2026-10-25T10:45:51Z
- last_update: 2026-10-25T09:15:51Z

## Done

- Step 3 (spec step 2): Rust encoder returns text or {reason,message,path}, writes rfc8785 itself, depth 1000 without a native cap (about 450-700 bytes of native stack per level, 1000 levels pass under ulimit -s 700; Windows main stack is 1 MiB: watch Windows CI). Fixtures regenerated so that plain objects with 2+ members are canonical (member order of plain output is undefined).

- Step 2: fixtures generated from the reference (tests/fixtures/{decode_cases,encode_cases,jcs_numbers}.lua + generate.lua). NaN message is sign-free; -0 decode cases already carry the new expectation (-0.0).

- Step 1: OQ-53 amended with the four owner decisions (specification; README, spec and ADR note come with the final docs step).

## Next steps

Owner decisions (2026-10-25), all to implement now: (1) the native encoder produces its own errors (reason, message, JSON Pointer path), including `rfc8785`; (2) `-0` is NOT handled natively: keep whatever yyjson produces, drop the special case and document it; (3) the oracle is replaced by fixtures (differential tests become expected-output fixtures); (4) native modules are required at run time everywhere: no fallback backend, a missing module raises a clear error.

1. Specify: README, schemas-and-contracts.md, ADR 0020 note, OQ-53 closed.
2. Encoder errors in Rust, tests first.
3. Decoder: remove every delegation to the reference backend (C).
4. Replace oracle tests with fixtures; delete `internal/reference.lua`, simplify `backend.lua`.
5. Docs, changelog, roadmap, CI check.

## Decisions taken (and where they are recorded)

## Doubts and questions for the owner

## Commands to re-run

```sh
```
