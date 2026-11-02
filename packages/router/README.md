# `hecate-router`

> Radix-tree router over URI templates (RFC 6570 level-1 subset) with 404/405 handling and reverse routing.

| | |
|---|---|
| Module | `hecate.router` |
| Rock | `hecate-router` |
| Layer | 2 — Protocol |
| Roadmap phase | 2 |
| Status | implemented (phase 2): templates, matching, 404/405, reverse routing, introspection |
| Lua | 5.5 (`lua >= 5.5, < 5.6`) |
| Depends on | [`core`](../core) |
| Used by | `hecate`, `kernel`, `openapi` |
| Native code | none |
| Specification | [http-and-routing.md](../../docs/architecture/http-and-routing.md) |
| Decisions | [ADR 0006](../../docs/adr/0006-declarative-routes-as-runtime-data.md) |
| Agent | [`pkg-router`](../../.claude/agents/pkg-router.md) |
| Repository | read-only mirror `hecate-framework/hecate-router`, generated from this directory (ADR 0017) |

## Responsibilities

- compile route tables into a radix tree at boot
- static > parameter > wildcard precedence
- `Allow` field for 405
- reverse routing (URI generation from route name and parameters)
- route table introspection

## Non-goals

- parameter validation (done by kernel with `schema`)

## Standards and references

- RFC 6570 (URI Template)
- RFC 3986 (URI)

## Public API

`local router = require("hecate.router")`. The reference is generated from the annotations
(`website/en/reference/router/`); the guide is [Route requests](../../website/en/how-to/route-requests.md).

- `router.Router(routes, options?)`: compiles a route table once, at boot.
  - `Router:match(method, raw_path)`: returns a `Match` (`status` 200, 204, 400, 404 or 405, `route`, `parameters`,
    `allow`, `allow_field`, `reason`). `raw_path` is `http.Request.path`.
  - `Router:url_for(name, parameters?)`: reverse routing.
  - `Router:routes()` and `Router:route(name)`: route table introspection.
  - options: `trailing_slash` (`"strict"` default, or `"ignore"`), `automatic_head` (default `true`),
    `automatic_options` (default `true`).
- `router.RouteTableError`: a `ConfigurationError` raised at boot; `context.reason` is `invalid_route`,
  `invalid_method`, `invalid_template`, `duplicate_name` or `ambiguous_route`.
- `router.template`: `parse(text, trailing_slash)` and `expand(template, parameters)`.
- `router.path`: `split(raw, trailing_slash)`, `decode(text)` and `encode(text, keep_delimiters?)`.

### Behaviour

- A path template is a subset of RFC 6570 level 1: literal segments, whole-segment parameters `{id}` and a last-segment
  wildcard `{path...}` (the notation is the router's own). Mixed segments such as `{id}.json` are refused.
- Precedence is static, then parameter, then wildcard, segment by segment, with backtracking. A route that does not serve
  the method is skipped for a lower-precedence one that does.
- 404 when no route has the path; 405 with a sorted `Allow` when the path exists for other methods; `HEAD` falls back to
  `GET` and `OPTIONS` answers 204 with `Allow`, unless a route is declared or the option is off.
- The request path is read as OQ-75 asks: each segment is percent-decoded on its own (`%2F` is data), dot segments are
  resolved first (RFC 3986 section 5.2.4; `%2E` is a dot), a malformed percent sequence or `%00` is status 400, and a
  wildcard never matches a segment whose decoded text holds `/`.
- The trailing slash is significant by default; the router never redirects.
- Ambiguous tables (the same method for the same paths) are rejected at boot, naming both routes.

### Security note for handlers

A `{param}` binds the *decoded* segment, so it may hold `/` or `\` (from `%2F`, `%5C`); a wildcard rejects segments holding `/`.
A handler that maps a parameter to a file must resolve it against a root, reject `\` and `:`, and never trust it as a path.

## Layout

```text
src/hecate/router/init.lua      public entry point
src/hecate/router/router.lua    Router
src/hecate/router/tree.lua      compiled radix tree over segments
src/hecate/router/template.lua  path templates
src/hecate/router/path.lua      request path decoding and dot segments
src/hecate/router/errors.lua    RouteTableError
tests/unit/                     unit, property (oracle) and example tests
examples/  benchmarks/match.lua
```
