---
description: The documentation generator for user projects: the site configuration, the pages generated from the contract and the configuration schema, LuaLS meta files, and the theme extension points.
hecate: "0.x"
lua: "5.5"
order: 3
---

<!-- Hand-written reference page (not generated): keep it in step with packages/doc/README.md. -->

# Project documentation

`hecate.doc` builds the documentation site of a user project with the same theme as the hecate website.
This page covers what a project can configure and what is generated for it, for hecate 0.x and Lua 5.5.

## Generated pages

`doc.project.build(options)` writes the guides of the project and the generated pages below the locale
directory, then runs the site build.

| Option | Adds |
|---|---|
| `document` | The API reference: `api/index.md` (the route table) and one page per tag, from the OpenAPI 3.1 document. |
| `configuration` | `configuration.md`, one row per key, from the JSON Schema of the configuration. |
| `code` | The code reference `reference/<name>/`, from the annotated sources in `<root>/src` (needs LuaLS). LuaLS reads the `.luarc.json` of the project and runs the plugin it declares: `root` must be a project you trust. |
| `pages` | The guides of the project. |

Generated pages carry a notice and are replaced at each build. A guide cannot overwrite one, and a generated page never overwrites a file that is not generated (a `BuildError` before anything is written). Generated pages that a build no longer produces are removed. A wrong option raises an `ArgumentError` naming it. The text that
comes from the contract is escaped, because it is data of the project and not Markdown.

## LuaLS meta files

`doc.project.meta(schemas, namespace)` returns the text of a `---@meta` file: an object schema becomes a
`---@class` with one `---@field` per property, and an enumeration becomes an `---@alias`. The output is
deterministic.

## Theme extension points

The site configuration has two options to give a project its own identity. Both name files of the `public/`
directory of the content root, which the build copies to the root of the site.

| Option | Effect |
|---|---|
| `logo` | A path, or `{ light, dark }`. Replaces the hecate logo in the header. The image is shown as it is. |
| `colors` | A CSS file loaded after the theme stylesheet. It overrides the custom properties of the colours (`--moon`, `--earth`, `--ink`, and so on). |

A path must be relative, without `..`, a scheme or a query. A file missing from `public/` fails the build
with a `BuildError`. The hecate marks are never recoloured. Template overrides are not offered.

Example of `public/colors.css`, with a dark variant:

```css
:root { --moon: #7a1f3d; }
:root[data-theme="dark"] { --moon: #f2b8c9; }
```
