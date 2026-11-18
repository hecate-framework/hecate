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

The site that `doc.project.build` writes is the documentation of the project's own team. By default it serves the
maintainers: it publishes only what you ask for. Pages have an audience: `user` (build, run and operate an application on the public API) or `maintainer`
(change the project itself: architecture, decisions, internals, CI and release).

| Where | Key | Meaning |
|---|---|---|
| Front matter of a page | `audience` | `user` or `maintainer`. Any other value fails the build with a `BuildError` naming the file. |
| Site configuration | `default_audience` | The audience of a page without the key. Default `maintainer`. |
| Site configuration | `audiences` | The audiences the site publishes. Default `{ "maintainer" }`. Ask for `{ "user" }` for a site for the users, or for both. |
| Site configuration | `audience_sites` | `"separate"` (default) or `"merged"`: what to write when several audiences are published. |

With several audiences published, the build writes one complete site per audience, `<out>/user/` and
`<out>/maintainer/`: each has its own pages, navigation, search index, sitemap, `llms.txt`, theme files and
`404.html`, and no page of the other audience. Give each audience its own home page (`index.md`). A link from a page
to a page of the other audience is reported like a broken link, naming the audience. With one audience the site is
written at `<out>/`. Set `audience_sites = "merged"` to write one combined site instead (the Hecate website does, for
now). The build report lists each site and its problems.

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

The site configuration has options to give a project its own identity. The first three name files of the `public/`
directory of the content root, which the build copies to the root of the site.

| Option | Effect |
|---|---|
| `logo` | A path, or `{ light, dark }`. Replaces the hecate logo in the header. The image is shown as it is. |
| `favicon` | A path, or `{ light, dark }`, of an `.svg`, `.png` or `.ico` file. Replaces the hecate favicon; the `type` attribute of the `<link rel="icon">` follows the extension. With a pair, each file carries a `prefers-color-scheme` media query. |
| `theme` | A CSS file (`.css`) loaded after the theme stylesheet. It overrides the custom properties of the theme: colours in light and dark, code highlighting, the three font families, radii, spacing and the width of the sidebar. It may declare its own `@font-face` for font files of `public/`. |

The option `sidebar_marker` (a boolean, default `false`) draws an accent bar at the left of the current page in the
sidebar. Without it, the current page is shown by a stronger weight and a subtle tint.

A path must be relative, without `..`, a scheme or a query. A file missing from `public/` fails the build
with a `BuildError`. The hecate marks are never recoloured. Template overrides are not offered. Every property,
what it affects and how to ship your own fonts are in [Theme tokens](theme-tokens.md).

Example of `public/theme.css`, with a dark variant (the dark set is written twice: for the system preference and for
the toggle):

```css
:root { --moon: #7a1f3d; --sans: system-ui, sans-serif; }
@media (prefers-color-scheme: dark) {
  :root:not([data-theme="light"]) { --moon: #f2b8c9; }
}
:root[data-theme="dark"] { --moon: #f2b8c9; }
```

## llms.txt

Set `llms = true` in the site configuration to have the build write `llms.txt` and `llms-full.txt` at the root of
the site, following the convention of [llmstxt.org](https://llmstxt.org). It is off by default: a project site
publishes nothing for language models until you ask. Without the key, a file `public/llms.txt` of your own is copied
as it is; with the key, a file of `public/` with one of these two names fails the build, because the generated file
would replace it.

- `llms.txt` has the site title, the description of the site, then a link to each published page with the `description` of
  its front matter, grouped by top-level section in the order of the navigation. The links are absolute when `url` is set.
- `llms-full.txt` holds the Markdown of the same pages one after the other, each after a `Source:` line with its URL, in
  the same order. Links between pages are kept as written in the sources.

Only the pages the site publishes appear: a page of an audience that is not published is left out. Only the default
locale is written. The output is deterministic.
