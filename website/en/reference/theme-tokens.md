---
description: Every custom property of the hecate.doc theme that a project can override, what it affects, and how to ship its own fonts.
hecate: "0.x"
lua: "5.5"
order: 4
---

# Theme tokens

The theme of `hecate.doc` is one stylesheet built on custom properties (CSS variables). A project changes the look of its
documentation site by overriding them in one CSS file, named by the site configuration key `theme`. This page lists
every property you can override and what it affects, for hecate 0.x and Lua 5.5. The configuration keys themselves are
in [Project documentation](project-documentation.md).

## Where the file goes

1. Put the CSS file in the `public/` directory of the content root, for example `public/my-theme.css`. The build copies
   `public/` to the root of the site.
2. Name it in `site.lua`: `theme = "my-theme.css"`. The path is relative to `public/`, ends with `.css`, and has no `..`,
   scheme, query or hidden segment. A file that is missing fails the build before anything is written.
3. The file is linked after the stylesheet of the theme, on every page, so a rule of the same specificity wins.

Only custom properties are an interface. The class names and the markup of the pages can change between versions.

```css
:root {
  --earth: #c2410c;
  --serif: "Fira Sans", system-ui, sans-serif;
  --radius-md: 12px;
}
```

## Colours

Colours come in two sets: the light set in `:root`, and the dark set. The theme applies the dark set when the reader's
system prefers it and the reader has not chosen light, or when the reader chose dark with the toggle. Your file must
override the dark set in the same two places, or the dark pages keep the colours of the theme:

```css
@media (prefers-color-scheme: dark) {
  :root:not([data-theme="light"]) { --earth: #ff8a4c; }
}
:root[data-theme="dark"] { --earth: #ff8a4c; }
```

| Property | What it affects |
|---|---|
| `--surface-100` | Page background, header, local navigation, and the background of a hovered or current sidebar entry. |
| `--surface-200` | Sidebar, code blocks, inline code, table headers, callouts, notices and the search button. |
| `--surface-300` | Raised elements: previous and next cards, copy buttons, the language menu, the search dialog. |
| `--border` | Hairlines: header, sidebar, tables, rules above second-level headings, footer. |
| `--border-strong` | Frames that must stay visible: buttons, the search button, cards, the bar of a quotation. |
| `--ink` | Body text and third-level headings. |
| `--ink-muted` | Secondary text: the "written for" line, outline, sidebar entries, captions. |
| `--moon` | Page title, first- and second-level headings, the note callout. |
| `--earth` | The accent: links, the current page and section, the focus ring, primary buttons, the tip callout. |
| `--on-earth` | Text on a filled `--earth` button. |
| `--success` | Inserted lines in highlighted diffs. |
| `--danger` | Deleted lines in highlighted diffs, the warning and caution callouts. |
| `--moonlight` | Declared by the brand kit; the current stylesheet does not use it. |

Keep a contrast ratio of at least 4.5:1 between each text colour and the surface it is set on (WCAG 2.2, 1.4.3), in both
sets. The build does not check it.

### Code highlighting

Highlighted code uses eight properties, in both sets.

| Property | What it colours |
|---|---|
| `--hl-keyword` | Keywords, storage words and tag names. |
| `--hl-string` | Strings. |
| `--hl-number` | Numbers and constants. |
| `--hl-function` | Function names. |
| `--hl-type` | Types and type annotations. |
| `--hl-parameter` | Parameters and attribute names. |
| `--hl-escape` | Escape sequences in strings. |
| `--hl-comment` | Comments, set in italic. |

Operators, punctuation and property names take `--ink`.

Diagrams (Mermaid) are drawn from `--surface-*`, `--ink`, `--ink-muted`, `--border-strong` and `--earth`, and are drawn
again when the colour set changes, so they follow your palette without further work.

## Fonts

| Property | What it sets | Default |
|---|---|---|
| `--serif` | Body text, headings, the title of the home page. | STIX Two Text |
| `--sans` | Interface text: header, sidebar, outline, tables, buttons, callout titles, search. | Fira Sans |
| `--mono` | Code blocks and inline code. | Fira Code |

Each is a CSS `font-family` list. The theme declares the families it ships (STIX Two Text, Fira Sans, Fira Code), so a
list can name one of them for another role: `--serif: "Fira Sans", sans-serif;` sets the body in Fira Sans. Sizes and
line heights are not properties.

To use your own font files, put them in `public/` and declare them in the same CSS file with `@font-face`. A relative
`url()` is resolved against the CSS file, so with `public/my-theme.css` and `public/fonts/body.woff2`:

```css
@font-face {
  font-family: "Body";
  font-weight: 400 700;
  font-display: swap;
  src: url("fonts/body.woff2") format("woff2");
}
:root { --serif: "Body", Georgia, serif; --sans: "Body", system-ui, sans-serif; }
```

Check the licence of every font you ship; the build does not. Two things stay as they are: the theme still preloads
STIX Two Text and Fira Sans in regular weight on each page, so a project that replaces both downloads them for nothing,
and the files are served by your host with the type it chooses, so serve `.woff2` as `font/woff2`. Without any font file,
a system font list works and costs nothing: `--sans: system-ui, sans-serif;`.

## Shape and layout

| Property | What it sets | Default |
|---|---|---|
| `--radius-sm` | Corner radius of small elements: inline code, keys, list entries, the focus ring. | 2px |
| `--radius-md` | Corner radius of blocks: code blocks, callouts, cards, buttons, dialogs. | 4px |
| `--space-1`, `--space-2`, `--space-4`, `--space-6`, `--space-12` | The spacing scale of margins and padding. | 4, 8, 16, 24, 48px |
| `--sidebar-width` | Width of the sidebar column, and the left margin of the footer beside it. | 272px |
| `--header-height` | Height of the sticky header, and the offset of everything that sticks below it. | 64px |
| `--local-nav-height` | Height of the bar of the outline and sidebar buttons on narrow screens. | 48px |

A logo is shown at 45 px high, so keep `--header-height` at 56px or more if you use one.

## What is not a token

- The properties `--show-light`, `--show-dark`, `--show-light-inline`, `--show-dark-inline`, `--callout` and `--icon`
  belong to the theme: they switch the logo and the toggle icon, and style callouts. Do not set them.
- The hecate marks are never recoloured. The `logo` key replaces the logo, and the image is shown as it is, never
  recoloured. Two hecate assets remain in a project site: the favicon, and the pattern strip of the home layout
  (`layout: home`). A project that wants neither avoids the home layout, and the favicon cannot be replaced yet.
- Templates are not overridable.

## Example

The documentation of the `hello` example, `examples/hello/docs`, has its own palette in both sets, its own radii and
sidebar width, the Fira Sans family for the body, a system font stack for the rest, and its own logo. Build it with
`lua examples/hello/build_docs.lua`.
