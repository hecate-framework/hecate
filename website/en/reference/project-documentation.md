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

The site that `doc.generate_project_documentation` writes is the documentation of the project's own team. By default it serves the
maintainers: it publishes only what you ask for. Pages have an audience: `user` (build, run and operate an application on the public API) or `maintainer`
(change the project itself: architecture, decisions, internals, CI and release).

| Where | Key | Meaning |
|---|---|---|
| Front matter of a page | `audience` | `user` or `maintainer`. Any other value fails the build with a `BuildError` naming the file. |
| Site configuration | `default_audience` | The audience of a page without the key. Default: the first of `audiences` (`maintainer` with the default `audiences`; `user` with `audiences = { "user" }`). |
| Site configuration | `audiences` | The audiences the site publishes. Default `{ "maintainer" }`. Ask for `{ "user" }` for a site for the users, or for both. |
| Site configuration | `audience_sites` | `"separate"` (default) or `"merged"`: what to write when several audiences are published. |

With several audiences published, the build writes one complete site per audience, `<output_dir>/user/` and
`<output_dir>/maintainer/`: each has its own pages, navigation, search index, sitemap, `llms.txt`, theme files and
`404.html`, and no page of the other audience. Give each audience its own home page (`index.md`). A link from a page
to a page of the other audience is reported like a broken link, naming the audience and telling a page published in another site (use an absolute URL or move the page) from one that is not published. A published locale without a page, and a site without a home page, are problems too, with the label or the file to add. With one audience the site is
written at `<output_dir>/`. Set `audience_sites = "merged"` to write one combined site instead. This is a deliberate, temporary exception for the Hecate website, which sets it until its restructure into a user part and a maintainer part; do not use it in a project. The build report lists each site and its problems.

A page of an audience that is not published is left out of the pages, the navigation, the search index, the sitemap
and the previous and next links. A link to it is reported like a broken link, and fails the build under `--strict`, so
that you notice it. Images next to a hidden page are still copied. A translation never publishes a page that the
original keeps back.

The configuration reference is a `maintainer` page. The code reference lists public symbols; the pages of `*.internal`
modules and of `private` or `package` classes are `maintainer` pages, generated only when `audiences` includes
`maintainer`. A field or method that is not public is never listed.

A worked example, a site for the users of a project, whose pages carry no `audience` key:

```lua
-- docs/site.lua
return {
  title = "Shop",
  audiences = { "user" },
  default_audience = "user", -- the default is the first audience: written here for clarity
}
```

Pages without the key are then `user` pages and are published; the configuration reference, a `maintainer` page, is
not. With the default `audiences`, a page without the key is a `maintainer` page.

An option or a key of `site.lua` that is not on its list is refused: an old name (`colors`, `theme`, `logo`) with the
name that replaced it, a typo (`audience`) with the closest key.

## Generated pages

`doc.generate_project_documentation(options)` writes the guides of the project and the generated pages below the
locale directory of the guides directory, then runs the site build. It is not the plain builder `doc.build`, which
only turns a content tree into a site. Every option has a default taken from the conventional layout of a project,
so `doc.generate_project_documentation({ application = application })` works from the project directory. A name that
ends in `_dir` is a directory and a name that ends in `_path` is a file; relative paths are relative to `project_dir`.

| Option | Default | Effect |
|---|---|---|
| `project_dir` | `.` | The directory of the project. |
| `guides_dir` | `docs` | The content root: `<guides_dir>/<locale>/*.md`, `public/` and `site.lua`. Generated pages are written into it. |
| `output_dir` | `docs/dist` | Where the static site is written. It may be below `guides_dir` (the default), but not `guides_dir` or `project_dir`, nor hold either, nor overlap `sources_dir`. |
| `site_configuration_path` | `<guides_dir>/site.lua` | The file that returns the site configuration; a path you give is relative to `project_dir`, the default is below `guides_dir`. `site_configuration` passes the table instead; giving both is an error. A missing file is a `BuildError` that names the remedies. |
| `application` | none | Adds `configuration.md`, one row per key, from the JSON Schema of the configuration the application was given (a `maintainer` page). The application is the only source: a project without one has no configuration reference. The schema is the single source of the secrets: a key marked `writeOnly: true` or `format: "password"` (`Configuration:schema()` does it for the secrets of `hecate.config`), or that holds such a key below it, never prints its default, its enumeration or its constant. |
| `package_name` | none | Asks for the code reference `reference/<package_name>/`, from the annotated sources in `sources_dir` (default `src`; needs LuaLS). LuaLS runs the plugins that the configurations it reaches declare: the project must be one you trust (see the warning below). |
| `licences_page` | off | Adds the third-party licences page: `true`, or a table `{ rocks_tree_dir, root_rocks, audience, include_bundled }`. |

The other options are `content_locale`, `file_system`, `clean_output_dir`, `fail_on_problems`, `last_updated`,
`language_server_path`, `language_server_config_path`, `theme_file_system` and `theme_files_dir`; they are described in
the README of the package.

Generated pages carry a notice (the first line after the front matter) and `generated: true` in their front matter, and are replaced at each build. A guide cannot overwrite one, and a generated page never overwrites a file that is not generated (a `BuildError` before anything is written); a guide that merely quotes the notice is not generated and is never touched. A generated page is never written through a symbolic link. Generated pages that a build no longer produces are removed. A wrong option, or one that is not on the list (an old name, a typo), raises an `ArgumentError` naming it (`context.argument`). With `fail_on_problems`, one `BuildError` lists every problem of the build, the licences page and the code reference.

A symbolic link in `guides_dir` or in `public/` is never followed: it is skipped with a problem, so that a link to a key file or to a parent directory cannot publish or loop. A tree deeper than 32 levels or larger than 100,000 entries is cut with a problem. A heading whose id is one the theme uses (`content`, `sidebar`, `search`, ...) is a problem: write `## Content {#project-content}`. The text that
comes from the schema is escaped, because it is data of the project and not Markdown.

The generator produces no HTTP API reference. The OpenAPI contract is the external documentation of the HTTP API: the application serves it (`/openapi.json`) and `hecate contract export` writes it. A viewer for it, such as Swagger UI, is your own wiring, for example a Docker compose file next to the application. The code reference above is another thing: it documents the Lua modules, classes and functions of `package_name`, from their LuaLS annotations, and no route.

> [!WARNING] Document only sources you trust
> The code reference runs LuaLS, and LuaLS runs arbitrary code. A plugin declared by any LuaLS configuration that it
> reaches is executed with full file and command access, as the user who runs the build. The configurations are the
> `.luarc.json` and `.luarc.jsonc` files and the `Lua.runtime.plugin` setting of `.vscode/settings.json` of the
> documented directory and of the project, and a `.luarc.json` inside the sources directory counts even when
> `language_server_config_path` points elsewhere. Without `language_server_config_path`, no `--configpath` is passed and
> LuaLS finds its configuration by itself. `lua-language-server` is found through `PATH` unless
> `language_server_path` names it, so `PATH` must be trusted too. The library does not warn; the command `hecate doc
> build` is to warn and let you stop (roadmap, `cli` item). Do not request a code reference for a project you do not
> control.

## LuaLS meta files

`doc.project.meta(schemas, namespace)` returns the text of a `---@meta` file: an object schema becomes a
`---@class` with one `---@field` per property, and an enumeration becomes an `---@alias`. The output is
deterministic.

## Theme extension points

The site configuration has options to give a project its own identity. The first three name files of the `public/`
directory of the content root, which the build copies to the root of the site.

| Option | Effect |
|---|---|
| `logo_path` | A path, or `{ light, dark }`. Replaces the hecate logo in the header. The image is shown as it is. |
| `favicon_path` | A path, or `{ light, dark }`, of an `.svg`, `.png` or `.ico` file. Replaces the hecate favicon; the `type` attribute of the `<link rel="icon">` follows the extension. With a pair, each file carries a `prefers-color-scheme` media query. |
| `stylesheet_path` | A CSS file (`.css`) loaded after the theme stylesheet. It overrides the custom properties of the theme: colours in light and dark, code highlighting, the three font families, radii, spacing and the width of the sidebar. It may declare its own `@font-face` for font files of `public/`. |

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

Set `generate_llms_txt = true` in the site configuration to have the build write `llms.txt` and `llms-full.txt` at the root of
the site, following the convention of [llmstxt.org](https://llmstxt.org). It is off by default: a project site
publishes nothing for language models until you ask. Without the key, a file `public/llms.txt` of your own is copied
as it is; with the key, a file of `public/` with one of these two names fails the build, because the generated file
would replace it.

- `llms.txt` has the site title, the description of the site, then a link to each published page with the `description` of
  its front matter, grouped by top-level section in the order of the navigation. The links are absolute when `site_origin` is set.
- `llms-full.txt` holds the Markdown of the same pages one after the other, each after a `Source:` line with its URL, in
  the same order. Links between pages are kept as written in the sources.

Only the pages the site publishes appear: a page of an audience that is not published is left out. Only the default
locale is written. The output is deterministic.
