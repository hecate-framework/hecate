# 0031 — A development-only JSON Schema validator validates the OpenAPI documents in CI

- **Status:** Accepted
- **Date:** 2026-11-14
- **Deciders:** project owner (choice (b) of OQ-130 and promotion to Accepted on 2026-11-14)
- **Packages:** openapi, schema (tests only), ci tooling (`tools/`, `.github/workflows/ci.yml`)
- **Related:** OQ-130 (issue [#203](https://github.com/hecate-framework/hecate/issues/203)), `packages/openapi/tests/support/structure.lua`, `packages/openapi/tests/external.lua`, [automation](../architecture/automation.md)

## Context

`openapi.build` produces OpenAPI 3.1 documents. The official description of that format is a JSON Schema (draft 2020-12),
`oas/3.1/schema/2026-11-05`, pinned by `packages/openapi/tests/external.lua` and downloaded by `fetch-fixtures openapi`.
It uses `$dynamicRef`, `unevaluatedProperties`, `if`/`then`/`else`, `format`, `pattern`, `patternProperties`,
`dependentSchemas`, `propertyNames`, `allOf` and `not`. `hecate.schema` (`conforms`) supports none of these, and extending it
to a full validator would be a large piece of code that has no use at run time (OQ-130).

Today the conformance test (`tests/support/structure.lua`) is a hand-written structural check of the fixed fields, compared
with the tables of the official schema. It is useful but it is our own reading of the specification: it cannot find what we
misread. A second opinion from an independent, complete validator is worth having, provided it never enters the product.

Measurements of 2026-11-14 (Linux, Node 22.23, Python 3.11), on the pinned schema and the golden document
`packages/openapi/tests/fixtures/shop.openapi.json`:

- **`ajv` 8.20.0 (`ajv/dist/2020`) with `ajv-formats` 3.0.1** compiles the schema (with `strict: false`; the strict mode
  rejects the schema, and the format `media-range` is unknown and must be registered) but reports 45 distinct errors on the
  golden document, among them every parameter `schema` ("must have required property 'schema'", `unevaluatedProperties`). The
  document is valid there: the Schema Objects are validated as Parameter Objects, that is, `$dynamicRef: "#meta"` is not
  resolved as the 2020-12 specification requires. `ajv` is therefore not a usable oracle for this schema as it stands.
- **Python `jsonschema` 4.26.0 (`Draft202012Validator`, with `referencing` 0.37.0)** resolves `$dynamicRef` correctly, reports
  one error on the golden document, and reports errors on a document with a broken `info`. The error is real:
  `paths./users/{id}.delete.security[0].bearer` is `{}` where a Security Requirement Object needs an array of scopes (`[]`).
  The cause is not analysed here (an empty Lua table is encoded as an object, or the test declares it so); it is a finding for
  the `openapi` item and the first thing the new check proves.

The CI workflow (`.github/workflows/ci.yml`) uses neither Node nor Python today: it relies on its own bootstrap of Lua and the
native toolchain. Both runtimes are documented as preinstalled on the GitHub-hosted runners
(`ubuntu-latest`, `macos-latest`, `windows-latest`), but this repository has not exercised that, so the workflow must not
assume it.

## Options considered

1. **(a) No validator.** Keep `structure.lua` and its comparison with the official tables only. Nothing new to trust and
   nothing to maintain; the full schema is never applied, so what we misread stays undetected.
2. **(b1) Node `ajv`** (2020-12 build, `ajv/dist/2020`, `ajv-formats`) through `npm ci --ignore-scripts` with a lockfile.
   MIT licensed; five small pure-JavaScript packages (`fast-deep-equal`, `fast-uri` BSD-3-Clause, `json-schema-traverse`,
   `require-from-string`); a lockfile with `sha512` integrity hashes; `npm view` confirms `ajv` 8.20.0 (integrity
   `sha512-Thbli+Ol…rBGA==`) and no install scripts. Consequence: it does not resolve `$dynamicRef` correctly for this
   schema (measured above), so it produces false errors on a valid document. Rejected on that evidence, not on principle.
3. **(b2) Python `jsonschema`** (`Draft202012Validator`) with `referencing`, installed with `pip install --require-hashes
   --only-binary :all:` from a pinned requirements file. MIT licensed (the dependencies `attrs`, `jsonschema-specifications`,
   `referencing`, `rpds-py` are MIT, `typing_extensions` is PSF-2.0). Handles `$dynamicRef`, `unevaluatedProperties`,
   `if`/`then`/`else`, `dependentSchemas` and the other keywords of the schema (measured above). `rpds-py` is a Rust
   extension distributed as binary wheels for the three platforms (nothing is compiled on the runner with
   `--only-binary`); `format` is annotation-only by default, as the 2020-12 specification has it, and asserting formats needs
   the `format` extra and its eight further packages, which is not taken.
4. **(b3) A validator written in Lua**, as a test-only module (or a rock). No new runtime and the same language as the rest;
   but it is the full validator that OQ-130 wants to avoid writing, with `$dynamicRef` and `unevaluatedProperties` (annotation
   tracking across `allOf`/`if`/`$ref`) being the subtle part, and a validator that we write and test ourselves is not an
   independent second opinion. Third-party Lua validators with 2020-12 support were not searched for.
5. **(c) Extend `hecate.schema` to validate JSON Schema documents.** The full validator, in the product, against the
   direction of OQ-130. Rejected by the owner's choice (b).

## Decision

Option (b) with Python `jsonschema` (option b2). Checkable form:

- The tool is **development-only and never ships**: it is in no rockspec, rock, Docker image, executable or installer; it is
  not in `THIRD_PARTY_NOTICES` (nothing of it is vendored or distributed); it is not needed to use Hecate or to run
  `lua tools/run.lua test` locally.
- **The Lua self-check stays the always-on check**: `tests/support/structure.lua` and its comparison with the official tables
  run in every test run, with no external tool.
- **CI runs `lua tools/run.lua validate-openapi`** (a task written in the next step). The task validates, with the pinned
  official schema (`fetch-fixtures openapi`), the documents that the tests produce: the golden file
  `packages/openapi/tests/fixtures/shop.openapi.json` and the documents of the build tests (written by the tests into
  `.hecate/` for the task to read). When the tool is absent the task **skips with a clear message locally** and **fails when
  `CI` is `true`**, so a green CI always means the documents were validated.
- **Pin and supply chain**: `jsonschema` **4.26.0** (MIT) with `referencing` 0.37.0, `jsonschema-specifications` 2025.9.1,
  `attrs` 26.1.0, `rpds-py` 2026.9.1 and `typing_extensions` 4.16.0, in a requirements file with `--hash=sha256:` entries for
  every artefact of the three platforms, installed with `pip install --require-hashes --only-binary :all: --no-deps`, in a
  virtual environment under `.hecate/` (git-ignored). Python comes from `actions/setup-python` pinned by commit hash like the
  other actions, with an exact Python version, on the three runners, in a dedicated job or step of `ci.yml`, not in the
  matrix of every package. **Caching** (CI only): `actions/setup-python` with `cache: pip` and `cache-dependency-path` set to
  the requirements file, and the finished virtual environment under `.hecate/` cached with `actions/cache` (pinned by commit
  hash), both keyed on the runner OS, the Python version and the hash of the requirements file, so that a change of any pin
  or hash gives a new key; on a hit the install is skipped, on a miss it runs with `--require-hashes` as above. The caches
  live only in the cache storage of GitHub Actions, scoped by branch (a pull request cannot write the cache of `main`);
  nothing of them enters the repository or any artefact. The interpreter itself is not cached: the action uses the toolcache
  of the runner or downloads it. Versions are those found on PyPI on 2026-11-14; the **real install with `--require-hashes`
  of the `validate-openapi` task (hashes of the requirements file) is their verification**; the owner accepted the ADR on 2026-11-14 on that basis. A change of any pin is a pull request that re-runs the check.
- **Licence**: every package of the set is MIT, MIT-compatible or PSF-2.0 (permissive). `check-licenses` only covers
  directories with a `VENDORED.md` under `packages/` and `THIRD_PARTY_NOTICES`; a tool installed into `.hecate/` is not
  vendored, so **no allowlist entry is needed**. If the requirements file were ever committed under `packages/`, it would
  need one.
- The validation asserts the structure (no format assertion). `format` of the official schema (`uri`, `email`,
  `media-range`) stays covered by `structure.lua`.
- Node `ajv` may be reconsidered if its `$dynamicRef` handling is fixed; this ADR is then superseded, not edited.

## Consequences

- Easier: the documents are checked against the complete official schema, by a validator written by others; our reading of the
  specification is no longer the only one. The first run already finds a document error (`security` requirement `{}`).
- Harder: a Python runtime and one pinned requirements file on the CI side only; a pin to maintain (updated with the
  pinned OpenAPI schema); about a minute of setup on each runner on a cache miss (to be measured by the job; Linux is the cheapest), a few
  seconds on a hit.
- To do (the `openapi` item of the roadmap): the `validate-openapi` task and its tests, the CI job on the three platforms,
  `docs/architecture/automation.md` catalogue entry, the test side that writes the documents, the fix of the finding above,
  and the update of the `packages/openapi/README.md` text on OQ-130.
- OQ-130 is resolved when the owner promotes this ADR; `conforms` stays unextended.

## Verification

- `ci.yml` runs `lua tools/run.lua validate-openapi` on Linux, macOS and Windows, after `fetch-fixtures openapi`.
- The task's tests (in `tools/tests`) check the three outcomes: validates a good document, rejects a bad one, and the
  skip (local) and failure (`CI=true`) when the tool is absent.
- The caches are keyed on the hash of the requirements file: a pin or hash change in a pull request misses the cache and
  installs again with `--require-hashes`.
- Review: no rockspec, Dockerfile or release script mentions Python or `jsonschema`; the requirements file has a hash for
  every line; no step of the workflow installs without `--require-hashes`.
