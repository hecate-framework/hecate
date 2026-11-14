# `hecate-openapi`

> OpenAPI 3.1 document assembly from the route table, schemas and project settings; served endpoint, export, lint and breaking-change diff.

| | |
|---|---|
| Module | `hecate.openapi` |
| Rock | `hecate-openapi` |
| Layer | 3 — Framework |
| Roadmap phase | 3 |
| Status | in progress — document assembly (step 1) and contract diff (step 2) implemented; served endpoint implemented in `kernel`; lint (`openapi.lint`) implemented; export to come |
| Lua | 5.5 (`lua >= 5.5, < 5.6`) |
| Depends on | [`core`](../core), [`schema`](../schema), [`router`](../router), [`json`](../json) |
| Used by | `cli`, `doc`, `hecate`, `kernel`, `test` |
| Native code | none |
| Specification | [schemas-and-contracts.md](../../docs/architecture/schemas-and-contracts.md) |
| Decisions | [ADR 0006](../../docs/adr/0006-declarative-routes-as-runtime-data.md) |
| Agent | [`pkg-openapi`](../../.claude/agents/pkg-openapi.md) |
| Repository | read-only mirror `hecate-framework/hecate-openapi`, generated from this directory (ADR 0017) |

## Responsibilities

- document assembly (info, servers, paths, components, security)
- `/openapi.json` and an interactive reference page in development
- export to JSON/YAML
- contract diff with breaking-change classification
- `openapi.lint(document)`: findings sorted by path and rule, as errors (`operation-id-missing`, `response-description-missing`, `response-undocumented`) or warnings (`description-missing`, `example-missing`, `tag-unused`)

## Non-goals

- client code generation (later)

## Standards and references

- OpenAPI 3.1
- JSON Schema 2020-12

## Public API

- `openapi.build(options)` assembles an OpenAPI 3.1 document table from `options.info` (`title`, `version`, `summary`, `description`, `terms_of_service`, `contact`, `license`), `options.servers`, `options.tags`, `options.external_docs` and `options.routes`, a list of route entries given as plain data (the shape of `hecate.kernel.RouteEntry`; the kernel is not required). Every route appears; the result does not depend on the order of the routes. `options.tags` is an ordered list `{ name, description?, external_docs? }` (display order is the list order; tags used by routes and not listed are appended alphabetically; a duplicate or non-string name is refused), `options.external_docs` is `{ url, description? }` rendered as `externalDocs`. The `operationId` is always the route `name`, which is mandatory (a missing or empty name is refused). The request body is `required` unless the entry has `content_optional = true`. A response declared with a problem class (a class that implements `core.Problem`, recognised by `core.implements`) needs the class attributes `status` (400 to 599) and `title` (a string, possibly empty); an invalid one is refused, naming the route and the response. A wildcard `{rest...}` of the router is documented as `{rest}`: OpenAPI has no wildcard segment, so the document loses the information that the parameter spans several segments. Response descriptions are the reason phrases of `core.status`, or the class of the code (`Success`, `Client Error`, ...) for a code without a phrase. Raises `ArgumentError` for invalid options, duplicate operations or names, and two different schemas under one component name.
- `openapi.encode(document, { pretty? })` writes the document as JSON with canonically ordered members (RFC 8785 section 3.2.3), so equal documents give equal bytes.
- `openapi.diff(old, new)` compares two document tables and returns a sorted list of changes `{ kind, breaking, path, message }` (sorted by `path`, `kind`, `message`; messages name rules and property names, never a value of the contract). Request schemas (parameters, body) are inputs: a removed path, operation, parameter, request media type or response, a newly required parameter or body, a narrowed type, a new required property, removed enum values and stricter bounds are breaking. Response schemas are outputs: a removed status, media type or property, a changed type, a property no longer required and added enum values are breaking. A response property that stops being required stays breaking (a client may rely on its presence). Removing an input property is breaking only when the new schema sets `additionalProperties: false`. A change to a keyword the diff does not analyse (`allOf`, `anyOf`, `oneOf`, `not`, `const`, `if`/`then`/`else`, `prefixItems`, `patternProperties`, ...) is reported as `schema_changed` and is breaking. Added operations, optional parameters, input widening and added response properties or statuses are not. Documentation and metadata changes are reported and never breaking: `default_changed`, `description_changed` (info, operation, parameter, request body, response, schema), `summary_changed` (info, operation), `example_changed` (`example` or `examples` of a schema, parameter or media type), `tags_changed` (as a set), `deprecated_changed` (either direction) and `security_changed`. The one exception is a security requirement that became stricter, so that a request which passed no longer does (an alternative removed, a scheme or scope added to one): `security_changed`, breaking. The operation `security` overrides the document one; an empty list or an empty alternative requires nothing. `$ref` into `components.schemas` is resolved. Raises `ArgumentError` for an argument that is not a table. Choices in OQ-129 (11).
- The served document is the kernel's: the `openapi` option of `hecate.kernel.Application` calls `build` and `encode` and serves the result with `GET /openapi.json` (OQ-134). Used by `kernel`.
- `openapi.VERSION` is `"3.1.0"`.
- Schemas go through `Schema:to_json_schema`; their `$defs` become `components.schemas` (OQ-89). The problem details schema (RFC 9457) is the component `ProblemDetails`, referenced with `application/problem+json` by the responses declared with a problem class.
- Choices taken conservatively are listed in OQ-129.

## Tests

- `tests/unit/` (run with `lua tools/run.lua test openapi`): assembly, golden file `tests/fixtures/shop.openapi.json`, diff.
- `tests/unit/conformance_test.lua`: conformance to OpenAPI 3.1. The structural self-check `tests/support/structure.lua`
  (fixed fields of the objects the assembly emits: required fields, no unknown fields, mandatory response description,
  declared and required path parameters, resolvable `$ref`) runs always over the golden document and the documents of
  the build tests. No checker of the repository can evaluate the official JSON Schema itself (`$dynamicRef`,
  `unevaluatedProperties`, `if`/`then`/`else`, `format`, `pattern`; OQ-130), so when the pinned official schema is
  downloaded (`lua tools/run.lua fetch-fixtures openapi`, `oas/3.1/schema/2026-11-05` of OAI/spec.openapis.org, pinned in
  `tests/external.lua`) the test compares the `required` and `properties` of each object with the fixed-field tables of
  the self-check. Without the download the comparison is skipped locally and fails in CI.
- Complete validation (development-only, ADR 0031): the conformance test also writes every document it builds into
  `.hecate/openapi-validate/<label>.json` (git-ignored), and `lua tools/run.lua validate-openapi` validates them and the
  golden file against the whole official schema (and its `schema-base` wrapper) with Python `jsonschema`. Locally, after
  `lua tools/run.lua test openapi` and `lua tools/run.lua fetch-fixtures openapi`, create the environment once
  (`python3 -m venv .hecate/venv-openapi`, then `.hecate/venv-openapi/bin/pip install --require-hashes --only-binary :all:
  --no-deps -r tools/ci/openapi-validator-requirements.txt`; `Scripts/pip.exe` on Windows) or point
  `HECATE_OPENAPI_VALIDATOR_PYTHON` at an interpreter that has `jsonschema`. Without them the task skips locally and fails
  when `CI` is `true`. The tool never ships.

## Layout (once implemented)

```text
src/hecate/openapi/init.lua   public entry point
src/hecate/openapi/internal/  components, contract diff, problem details, status phrases
tests/unit/  tests/integration/  tests/fixtures/
examples/    benchmarks/
```
