---
description: The documentation generator for user projects: the site configuration, the pages generated from the configuration schema, LuaLS meta files, and the theme extension points.
hecate: "0.x"
lua: "5.5"
order: 3
---

<!-- Hand-written reference page (not generated): keep it in step with packages/doc/README.md. -->

# Project documentation

`hecate.doc` builds the documentation site of a user project with the same theme as the hecate website.
This page covers what a project can configure and what is generated for it, for hecate 0.x and Lua 5.5.

## Audiences

The site that `doc.project.build` writes is the documentation of the project's own team, and it publishes only what
you ask for. Pages have an audience: `user` (build, run and operate an application on the public API) or `maintainer`
(change the project itself: architecture, decisions, internals, CI and release).

| Where | Key | Meaning |
|---|---|---|
| Front matter of a page | `audience` | `user` or `maintainer`. Any other value fails the build with a `BuildError` naming the file. |
| Site configuration | `default_audience` | The audience of a page without the key. Default `user`. |
| Site configuration | `audiences` | The audiences the site publishes. Default `{ "user" }`. Ask for `{ "user", "maintainer" }` to publish everything. |

A page of an audience that is not published is left out of the pages, the navigation, the search index, the sitemap
and the previous and next links. A link to it is reported like a broken link, and fails the build under `--strict`, so
that you notice it. Images next to a hidden page are still copied. A translation never publishes a page that the
original keeps back.

The configuration reference is a `maintainer` page. The code reference lists public symbols; the pages of `*.internal`
modules and of `private` or `package` classes are `maintainer` pages, generated only when `audiences` includes
`maintainer`. A field or method that is not public is never listed.

## Generated pages

`doc.project.build(options)` writes the guides of the project and the generated pages below the locale
directory, then runs the site build.

| Option | Adds |
|---|---|
| `configuration` | `configuration.md`, one row per key, from the JSON Schema of the configuration (a `maintainer` page). The default of a secret key is never printed: mark the key `writeOnly: true` or `format: "password"` in the schema, or list its path in the option `secrets`. |
| `code` | The code reference `reference/<name>/`, from the annotated sources in `<root>/src` (needs LuaLS). LuaLS reads the `.luarc.json` of the project and runs the plugin it declares: `root` must be a project you trust. |
| `pages` | The guides of the project. |

Generated pages carry a notice and are replaced at each build. A guide cannot overwrite one, and a generated page never overwrites a file that is not generated (a `BuildError` before anything is written). Generated pages that a build no longer produces are removed. A wrong option raises an `ArgumentError` naming it. The text that
comes from the schema is escaped, because it is data of the project and not Markdown.

The generator produces no API reference. The OpenAPI contract is the external documentation of the API: the application serves it (`/openapi.json`) and `hecate contract export` writes it. A viewer for it, such as Swagger UI, is your own wiring, for example a Docker compose file next to the application.

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
