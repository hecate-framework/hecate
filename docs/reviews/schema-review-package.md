# `schema` item: `/review-package` findings

Read-only review of the `schema` roadmap item (pull request 54: `packages/schema`, the small related changes of
`core` and `json`, the documentation and the CI wiring) by seven reviewer agents (architect, API, terminology,
security, tests, performance, developer experience with portability), run on 2026-11-08 at the head of
`claude/relay-schema`. No blocker in code. Status column: **open** until fixed (then "fixed" with the commit) or moved
to a roadmap item or an owner decision. Findings come from reading plus probes run by the security reviewer; each fix
reproduces the failure first.

## Major

| Id | Lens | Finding | Fix | Status |
|---|---|---|---|---|
| S1 | security | `unique_items` is quadratic and outside the work budget: 20000 distinct integers (about 110 KB) took 11.3 s of CPU; no default `max_items` | Hash scalar items, compare tables pairwise, charge the budget per comparison | fixed (5cf3b69) |
| S2 | security | The Lua `pattern` runs on unbounded input even when `max_length` or `invalid_utf8` already failed; `%w+@` on 20000 letters took 2.5 s | Skip pattern and format once a length or encoding violation is recorded; bound the length a pattern sees; document anchoring | fixed (5cf3b69) |
| S3 | security | Declaration-time pattern check is incomplete: `string({pattern="ab%"})` is accepted, then `validate` raises a raw Lua error (a 500) | Probe with a subject that walks the whole pattern, and wrap the match in `pcall` reporting a violation | fixed (5cf3b69) |
| S4 | security | Violation lists are unbounded: 50000 undeclared keys gave 50000 violations, each echoing the key twice | Cap violations per call (for example 100 then one truncation entry); truncate the echoed key | fixed (5cf3b69) |
| S5 | API | Violation codes have no stable documented list; `additional_property` is singular while the option is `additional_properties`; the short code and the dotted error code are different namespaces | Add a violation code table to the specification, an alias type for the codes, decide the rename now | fixed (3130f07, 116ae90) |
| S6 | API | Internals annotated as public fields (`validator`, `coercer`, `relaxed_validator`, `builder`, `representer`, `prefilter`, `_limits`); `coerce` and `to_json_schema` documented twice; `members` annotated as a field | Mark internals private, remove the duplicated field forms, make `members` a real method | fixed (3130f07, 116ae90) |
| S7 | API | `coerce` and `build` return `true, value` or `false, violations` annotated as `any`; `validate` returns another shape | Add return overloads and document the convention once | fixed (3130f07, 116ae90) |
| S8 | API | Option annotations contradict between `schema.lua` and `init.lua` (`integer`, `number`, `string`, `array`, `enumeration` over a core enumeration); README API lines incomplete | One option class per constructor, README aligned | fixed (3130f07, 116ae90) |
| S9 | architect | The specification promises `refine`, `generate`, `generate_invalid`, and the README Responsibilities list `---@meta` generation and property-based generators, with no roadmap home; the specification still shows `map(key, value)` | Mark them not yet implemented in the specification and README, add roadmap lines (`test` carries generators, `doc` or `cli` carries `---@meta`), open an entry for `refine` | fixed (116ae90, fdae972); refine is OQ-97 |
| S10 | architect | The JSON Schema keywords outside the emitted subset (`allOf`, `not`, `if`, `contains`, tuples, `patternProperties`, `propertyNames`, `dependent`, `unevaluated`, `$id`, anchors, remote `$ref`, `content`) are recorded only in a test header | Document them as deliberate limits in the README, the explanation page and the French mirror; record the scope statement | fixed (116ae90, fdae972) |
| S11 | DX | A doc comment says undeclared properties are allowed by default for request content, while the code and how-to say they are rejected | Fix the comment (it feeds the generated reference) | fixed (3130f07, 116ae90) |
| S12 | DX | Pattern refusal and warning say what is wrong but not that Lua validation still works nor how to rewrite; the logger warning carries pattern and reason only in fields | One actionable clause in the message; pattern and reason in the warning text | fixed (3130f07, 116ae90) |
| S13 | DX | The how-to starts with edge cases and never shows turning `check` violations into a client-readable error | Reorder (declare, validate, class, build, PATCH, represent, then edge cases) and add a violations-to-client example | fixed (116ae90, fdae972) |
| S14 | tests | The invariant emitted schema equals Lua validation is checked on 48 fixed values and 30 hand-picked schemas; `format` and `pattern` are not in the differential; no test pins that `format` is only an annotation when emitted | Seeded property-based differential (print the seed), a pinning test for `format` | fixed (d460c46, ec05efc) |
| S15 | tests | The suite runner excuses any disagreement once a whole float appears anywhere, and a fractional `multipleOf` excuses the group; no minimum on emission agreement, no cap on gaps | Allow the gap only where Lua says invalid and the official says valid at an integer position; add guards and pinned skip counts | fixed (5e3e8f2) |
| S16 | tests | Timing assertions (0.5 s to 2 s on `os.clock`, wall time on Windows) are fragile on slow runners; two 200000-node hostile chains are heavy | Assert step counts growth, widen or drop clock bounds, reduce chains to about 20000 | fixed (9801f4d) |

## Minor

| Id | Lens | Finding | Fix | Status |
|---|---|---|---|---|
| s1 | security | A `default` table is shared and mutable through `schema.options.value`, which changes it for every later request (breaks immutability) | Keep it in a closure and hand out copies | fixed (5cf3b69) |
| s2 | security | `represent` and `build` collide with class members: a declared property named like a method represents the method (function, then an encode error) and a client string can overwrite a method on a built instance | Refuse declared names that resolve to a class member in `of`; skip function values in `represent` | fixed (5cf3b69) |
| s3 | security | Boolean `false` is lost: coercing `"false"` in a map is refused and a top-level `default(boolean, false)` returns nil (both fail closed) | Explicit if and else instead of and-or | fixed (5cf3b69) |
| s4 | security | `email` accepts control characters and any length | Reject control characters, maximum 254 bytes | fixed (5cf3b69) |
| s5 | security | Lua matches bytes and ECMA without the u flag matches UTF-16 units: the invariant holds for ASCII input only | Document it in the README and the explanation page | open |
| s6 | security | Per-call state is module state; a yielding `__index` during `represent` or `build` in a coroutine could interleave two calls | Document it | open |
| s7 | security | The encoder entry budget could hold hundreds of MB at 8M entries; a repeated key from an iterator encodes duplicate keys | Tighter budget; refuse or deduplicate a repeated key | open (json) |
| t1 | terminology | DTO and data transfer object used for inline schemas; the French glossary row blesses it | Say inline schema; delete the French row | fixed (116ae90, fdae972) |
| t2 | terminology | body used for the declaration of a schema (collides with content) | Say definition | fixed (116ae90, fdae972) |
| t3 | terminology | header used alone where the glossary says header field | Say header fields | fixed (116ae90, fdae972) |
| t4 | terminology | validator names the compiled closure; no glossary row; build untranslated in French | Add rows (validator internal, build, fail-fast mode, minor units) | fixed (116ae90, fdae972) |
| t5 | terminology | `Record` class name for read-only options collides with the glossary meaning of record | Rename to Options (low priority) | fixed (3130f07, 116ae90) |
| a1 | API | Parameter names differ for the same role (`item`, `value_schema`, `inner`); union documented as alternatives and as list | Align before 0.1 | fixed (3130f07, 116ae90) |
| a2 | API | Glossary lacks represent and the union collision with the relational union; `allocate` doc comment claims to be the only `setmetatable` site; `weak_table` modes unnamed | Add one glossary sentence each, reword the comment, name the mode alias | fixed (3130f07, 116ae90) |
| x1 | DX | Declaration messages do not list valid choices (`unknown format`, `unknown option`), the pattern check message is circular, type messages do not name the received type | List choices, show the underlying error, name the received Lua type | fixed (3130f07, 116ae90) |
| x2 | DX | Snippet style differs (call with parentheses versus braces only); `docs/developer-experience.md` shows `Class.representation` and implicit represent, which the package does not have | Pick one style; routes item settles the response mapping | snippet style fixed (116ae90); the `Class.representation` text of `docs/developer-experience.md` stays open (routes item) |
| x3 | DX | No shipped interface for a class that has a schema: each user declares their own | Ship one in `hecate.schema` | fixed (3130f07, 116ae90) (`schema.HasSchema`) |
| q1 | tests | Several weak assertions (only ok), a manually restored limit without protection, missing coverage of every bad option, no round trip decode build represent encode, no seeded test of the pattern translator and format validators | Write the seven tests listed by the reviewer | fixed (d460c46, 9801f4d, 89b076e, 386e5d3) except the weak assertions of older tests (see Fix pass C) |

## Performance

Measured on a Linux VM (4 cores, `bench schema/validate`, 5 runs, noise 4 to 20 percent): validate record 331k per
second, array of 100 items 3.1k, union 413k; coerce about half of validate because it copies every object then
validates; build record 190k. Each experiment below was run on a patched copy, 10 percent or more counts, 5 percent or
less is noise. Absolute figures must come from the owner hardware (`benchmarks/README.md`).

| Id | Finding | Fix | Status |
|---|---|---|---|
| P1 | Path strings are built on every successful visit (object, array, map validators, coercers, representers); removing the concatenations gave record +25 to 30 percent and array of 100 +30 percent (upper bound) | Pass the parent path, a token and a parent link, and join the path only where a violation is appended; or keep one reusable segment stack | fixed (8dca32e) |
| P2 | The memoisation store (3 tables plus one per union) is allocated even when no union is nested; disabling it for the benchmark union gave validate +35 to 45 percent and coerce +35 percent | Use the memo only where a node can be revisited (inside an alternative attempt), create the answers table lazily; keep the OQ-91 bound (test the exponential case before and after) | fixed (5fc6d89) |
| P3 | The `guarded` wrapper costs an extra closure call, the budget call, a table read and two global writes per container; replacing it by the inner function gave record +13 to 26 percent | Keep it (it enforces OQ-50 and OQ-91) but make it cheaper: cache the limits in upvalues, inline the step test, fold it into the object and array closures | measured, not worth it (see Fix pass D) |
| P4 | The benchmark has no represent, class build, tagged union, recursive union, failing input, string with `min_length` or `format`, or `build` with `coerce` | Add these scenarios before optimising P2 and P3 | fixed (7ba31a5, 00289db) |
| P5 | Class build costs about 75 percent more than a plain object build (3 tables plus one weak-table insertion) | Fill the instance directly; only if `plaintext` or `json` show it | measured, kept: about 1 µs per instance, not on the path of either scenario; to look at again with the Phase 4 database scenarios ([Phase 2 benchmarks](phase-2-benchmarks.md)) |
| P6 | `format` validators cost 0.6 to 1.1 microseconds per call; `utf8.len` about 85 nanoseconds per string | Measure with a realistic mix before touching | measured, kept provisionally: about 1.1 µs per call (email); to judge again with the `validation` scenario ([Phase 2 benchmarks](phase-2-benchmarks.md)) |

The encoder `__pairs` check costs about 6 percent on a document made only of marked containers (the output of
`represent`) and nothing for a plain table: not a finding. The roadmap Benchmarks item now carries P5 and P6 as a schema
entry, to be judged with the `plaintext` and `validation` scenarios.

## Fix pass A (2026-11-08)

Fixed in commit 5cf3b69 with tests in `packages/schema/tests/unit/hardening_test.lua` and `represent_test.lua`: S1 to S4 and
s1 to s4, and the round trip of an explicit null (test q1, item 2). Owner decision of 2026-11-08 on the null round trip:
`represent` consults the presence set, so a nullable attribute that is nil on an instance made by `build` and sent as null is
represented as null; an instance that was not built still omits a nil attribute; a hand-set `json.null` stays null. The
second union pass of `represent` is memoised per alternative.

## Fix pass B (2026-11-08)

Fixed in commits 3130f07 (code and tests: `packages/schema/tests/unit/review_b_test.lua`), 116ae90 (documentation, how-to, glossary) and
fdae972 (French pages, changelog): S5 to S13, a1, a2, t1 to t5, x1, x3 and the snippet style of x2. Names chosen: the interface
`schema.HasSchema` (no glossary term exists; `FileSystem` and `Stream` are the other interfaces of the repository, nouns), the
alias `hecate.schema.ViolationCode`, the option classes `StringOptions`, `IntegerOptions`, `NumberOptions`, `ArrayOptions`, `MapOptions`,
`ObjectOptions` and `BuildOptions`, the internal `hecate.schema.Options` (was `Record`), `hecate.core.WeakMode`. Parameter convention:
`item` (array), `value` (map), `inner` (wrappers), `alternatives` (union).

## Fix pass C (2026-11-08)

Tests only, plus one private accessor, `schema._steps()` (the steps of the last call, next to `schema._limits`). Commits d460c46
(seeded differential, round trip, `tests/support/prng.lua` and `protected.lua`), 5e3e8f2 (suite runner), 9801f4d (step counts in
place of clocks), 89b076e (bad options, violation codes), 386e5d3 (robustness of the translator and the formats), ec05efc
(typecheck, changelog). No production bug was found by the new tests. Findings of the new tests that stay as they are:

- The order of the violations for undeclared properties was thought to follow `next`. Fix pass D found that the validators
  already sorted them (bytewise); the part that did follow `next` was the coercion violations of a `map` (fixed in 00289db).
- The refusal of `NaN` or an infinite number for an option says "must be a number, got number" (the received type is not
  informative there). Cosmetic.
- `schema.of` with a module name or a table that does not resolve is accepted at declaration and refused when the schema is
  used (it is lazy for cycles); the test pins that behaviour.
- The official suite runner depended on `pairs` order for the reason a group is skipped (a different bucket from run to run);
  the keys are now visited in sorted order, and the 42 skip reasons are pinned with their counts.
- The test matcher of ECMA expressions read `[\s\S]` (the translation of `.`) as the two letters `s` and `S`; it now handles the
  two classes inside a set. The earlier differential passed only by coincidence for `.-z`.

Not done, with the reason: the weak assertions of older tests (several tests only assert that `ok` is true) were not rewritten
one by one; the new tests cover the same ground more strongly (round trip, differential, codes) and a sweep would touch most
files for little gain. The generator of the differential never produces `pattern`, `format`, a whole float where an integer is
expected, a fractional `multiple_of` or invalid UTF-8 (each documented in `differential_test.lua`).

## Fix pass D (2026-11-08)

Performance, judged by `lua tools/run.lua bench schema/validate --yes` (5 runs, medians; the host was reported as not quiet,
a shared 4-core VM; noise per scenario 3 to 20 percent, one scenario at 60 percent; absolute numbers are indicative only).
Commits: 7ba31a5 (P4, scenarios), 5fc6d89 (P2), 8dca32e (P1, `paths_test.lua`), 00289db (determinism, tests).

| Scenario (operations per second) | Baseline (max/min) | Final (max/min) | Change |
|---|---|---|---|
| validate record | 287k (1.15) | 311k (1.06) | +8% |
| validate array of 100 | 2.75k (1.02) | 3.37k (1.05) | +22% |
| validate union | 403k (1.06) | 574k (1.11) | +42% |
| coerce record | 149k (1.06) | 162k (1.10) | +9% |
| coerce array of 100 | 1.24k (1.03) | 1.69k (1.04) | +36% |
| coerce union | 182k (1.15) | 248k (1.60) | +36% |
| build record | 166k (1.07) | 181k (1.12) | +9% |
| represent record | 344k (1.09) | 388k (1.37) | +13% |
| represent array of 100 | 2.46k (1.05) | 3.79k (1.05) | +54% |
| build class-bound | 320k (1.08) | 339k (1.06) | +6% |
| build class-bound nested | 178k (1.14) | 189k (1.06) | +6% |
| validate tagged union | 866k (1.22) | 868k (1.06) | 0% |
| build tagged union | 484k (1.09) | 479k (1.15) | -1% |
| represent tagged union | 872k (1.12) | 902k (1.12) | +3% |
| validate twins, depth 30, invalid | 7.16k (1.03) | 7.27k (1.03) | +1% |
| validate twins, depth 30, valid | 37k (1.07) | 40k (1.08) | +10% |
| validate failing record | 33k (1.03) | 30k (1.08) | -8% |
| validate failing union | 57k (1.04) | 56k (1.12) | -1% |
| validate string with a format | 631k (1.11) | 680k (1.07) | +8% |
| validate string with a length | 3.44M (1.16) | 3.86M (1.06) | +12% |
| build with coerce, query | 120k (1.08) | 139k (1.06) | +16% |

The scenarios of a map (added with the determinism fix) were measured against the revisions before and after P1 only:
coerce 40k to 61k and validate 86k to 133k per second (3 runs each).

- P2 (fixed): the memoisation answers and stores only in fail-fast mode (validation) or inside an alternative attempt
  (coercion and the second pass of `represent`), and the stores are created by the first stored answer. Validate union
  +44 percent, coerce union +31 to 42 percent; the `twins` step caps of `union_cost_test.lua` are unchanged.
- P1 (fixed): validators, coercers and representers pass `at`, the number of tokens of the path of the node, and keep the
  tokens in one stack (`segments`); `path_to(at)` joins it where a violation is recorded, and in fail-fast mode no path is
  built (violations there are dropped). Array of 100: validate +22, coerce +36, represent +54 percent. Cost: a failing input
  pays one join per violation; the benchmark record fails almost everywhere and is 8 percent slower. A first version that
  joined in fail-fast mode too made a failing union 80 percent slower, hence `where`. `paths_test.lua` was run against the
  previous revision: the paths are byte-identical (nested object, array, map, union, tagged union, escaped tokens, long key,
  siblings after a deep descent, depth limit). One difference: a non-string key of an `any` value that is copied is now
  escaped like the others (it was concatenated as is; its text cannot contain `~` or `/` for the types JSON can hold).
- P3 (measured, not worth it): caching `max_steps` in an upvalue (refreshed by `reset_work`), the inline step test and the
  guard folded into the object validator gave at most +5 percent on the array and nothing (-3 percent) on the record, below
  10 percent and inside the noise after P1 and P2. Reverted; the review estimate (13 to 26 percent) held only before them.
- Determinism: the undeclared properties of an object were already reported in byte order. The coercion violations of a
  `map` followed `next`; a failed map coercion is now visited again in byte order (success path unchanged: 3 runs, within 3
  percent). Remaining and not changed: `represent` of a map or an `any` raises the error of the first failing member in `next`
  order (a response bug, one violation).
- P5 and P6: measured and kept by the Benchmarks item ([Phase 2 benchmarks](phase-2-benchmarks.md)).

## Owner decisions raised by the review

1. Rename the violation code `additional_property` to `additional_properties` (S5): recommended before 0.1.
2. Roadmap homes for `refine`, generators and `---@meta` generation, and an entry for `refine` (S9).
3. Statement that JSON Schema keywords outside the emitted subset are out of scope until a consumer needs them (S10).
4. Ship a shared interface requiring a class-level `schema()` in `hecate.schema` (x3).
5. The `logger` option of `schema.string` follows OQ-86 (owner decision); the review only asks to document it.
