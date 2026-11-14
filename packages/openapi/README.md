# `hecate-openapi`

> OpenAPI 3.1 document assembly from the route table, schemas and project settings; served endpoint, export, lint and breaking-change diff.

| | |
|---|---|
| Module | `hecate.openapi` |
| Rock | `hecate-openapi` |
| Layer | 3 — Framework |
| Roadmap phase | 3 |
| Status | in progress — document assembly (step 1) and contract diff (step 2) implemented; served endpoint, export and lint to come |
| Lua | 5.5 (`lua >= 5.5, < 5.6`) |
| Depends on | [`core`](../core), [`schema`](../schema), [`router`](../router), [`json`](../json) |
| Used by | `cli`, `doc`, `hecate`, `test` |
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
- lint rules (operation ids, descriptions, examples)

## Non-goals

- client code generation (later)

## Standards and references

- OpenAPI 3.1
- JSON Schema 2020-12

## Public API

- `openapi.build(options)` assembles an OpenAPI 3.1 document table from `options.info` (`title`, `version`, `summary`, `description`, `terms_of_service`, `contact`, `license`), `options.servers` and `options.routes`, a list of route entries given as plain data (the shape of `hecate.kernel.RouteEntry`; the kernel is not required). Every route appears; the result does not depend on the order of the routes. Raises `ArgumentError` for invalid options, duplicate operations or names, and two different schemas under one component name.
- `openapi.encode(document, { pretty? })` writes the document as JSON with canonically ordered members (RFC 8785 section 3.2.3), so equal documents give equal bytes.
- `openapi.diff(old, new)` compares two document tables and returns a sorted list of changes `{ kind, breaking, path, message }` (sorted by `path`, `kind`, `message`; messages name rules and property names, never a value of the contract). Request schemas (parameters, body) are inputs: a removed path, operation, parameter, request media type or response, a newly required parameter or body, a narrowed type, a new required property, removed enum values and stricter bounds are breaking. Response schemas are outputs: a removed status, media type or property, a changed type, a property no longer required and added enum values are breaking. Added operations, optional parameters, input widening and added response properties or statuses are not. `$ref` into `components.schemas` is resolved. Raises `ArgumentError` for an argument that is not a table. Choices in OQ-129 (11).
- `openapi.VERSION` is `"3.1.0"`.
- Schemas go through `Schema:to_json_schema`; their `$defs` become `components.schemas` (OQ-89). The problem details schema (RFC 9457) is the component `ProblemDetails`, referenced with `application/problem+json` by the responses declared with a problem class.
- Choices taken conservatively are listed in OQ-129.

## Layout (once implemented)

```text
src/hecate/openapi/init.lua   public entry point
src/hecate/openapi/internal/  components, contract diff, problem details, status phrases
tests/unit/  tests/integration/  tests/fixtures/
examples/    benchmarks/
```
