# 0033 — Vendored browser libraries: Mermaid diagrams in the documentation theme

- **Status:** Accepted
- **Date:** 2026-11-17
- **Deciders:** project owner (option (a) of OQ-128 chosen on 2026-11-13 and reaffirmed on 2026-11-17; accepted by the owner in chat on 2026-11-18)
- **Packages:** doc (theme and renderer), website, and the CI tooling (`check-licenses`)
- **Related:** OQ-128 ([issue #194](https://github.com/hecate-framework/hecate/issues/194)), [ADR 0012](0012-website-generator.md), [ADR 0022](0022-doc-dependencies.md) (precedent for third-party material of the generator), [ADR 0032](0032-unicode-normalisation-packages.md) (precedent for a licence notice and pinned data), [documentation.md](../architecture/documentation.md), OQ-34 (vendored theme assets), `THIRD_PARTY_NOTICES`

## Context

The explanation pages need diagrams (the dependency graph of the packages in `overview.md` is already a
Mermaid block). The site builder shows a ` ```mermaid ` fence as a code block, and only images are drawn
(OQ-128). The owner decided on 2026-11-13 that Mermaid diagrams must render, through a vendored copy of the
`mermaid.js` library (no CDN) loaded only on the pages that hold a diagram and run in the reader's browser, and
that an ADR written `Proposed` comes first, because the library is third-party code that the theme ships.

Facts that bound the decision, measured on 2026-11-17:

- The latest stable release on the npm registry is `mermaid` 12.3.0 (licence MIT). Its file
  `dist/mermaid.min.js` is a single self-contained classic script of 5 537 838 bytes (1 581 915 bytes
  gzipped) that defines one global. The ESM build splits into 210 chunk files (25 MB) that a browser loads
  lazily by diagram type; a module script cannot import them from a `file:` URL, so a site opened from disk
  would show no diagram.
- The file bundles about twenty packages (DOMPurify, d3, dagre, cytoscape, KaTeX, chevrotain, ELK and others).
  Their licences, as declared on npm: MIT (most), ISC (`d3`), BSD-3-Clause (`d3-sankey`), Apache-2.0
  (`chevrotain`), MPL-2.0 OR Apache-2.0 (`dompurify`) and EPL-2.0 OR GPL-3.0-or-later (`elkjs`). No licence forbids
  redistributing the unmodified file; the GPL option of `elkjs` is not used and the EPL-2.0 applies to an
  unmodified copy.
- The text of a diagram is written by the author of a page, who may be a contributor to a user project: it is
  untrusted input. Mermaid renders SVG and can render labels as HTML (`foreignObject`) in its `loose`
  security level.
- `hecate.doc` already ships small vanilla scripts (`theme.js`, `theme-init.js`) and vendored fonts
  (OQ-34, `THIRD_PARTY_NOTICES`). The brand kit (owner decision of 2026-10-13: everything visual comes from the
  brand kit) forbids gradients, shadows and glows, requires nearly square corners and earth as the single
  accent; the theme exposes the tokens as custom properties for the light and the dark theme.

## Options considered

1. **A vendored copy of the browser bundle, rendered in the reader's browser** (the owner's option (a)).
   One 5.5 MB file, loaded only by pages with a diagram; no build-time dependency; works served or opened from
   disk; the diagram follows the colour theme the reader chooses. Cost: third-party code runs in the page and
   the repository holds a large file.
2. **Render to SVG at build time with `mermaid-cli`.** Pages stay static and need no script. Cost: Node and a
   headless browser in every build of every user project (the builder is Lua and Rust only, ADR 0022), a second
   toolchain to pin and secure in CI on three platforms, and one SVG per colour theme (or a fixed
   colour) instead of a diagram that follows the theme. Set aside by the owner.
3. **A Rust renderer.** Compiled into the native module (ADR 0021). The Rust implementations are young and
   cover few diagram types, so a page that renders on one version would fall back to code on another. Set
   aside by the owner.
4. **Hand-drawn SVG only.** No dependency and the best control, but every diagram is an image to draw and to
   keep in step with the text, and `overview.md` already holds Mermaid. Set aside by the owner; it stays
   available to an author who needs a diagram no renderer draws well.
5. **The ESM build with its chunks.** Loads less for a simple diagram, but 210 files, a module loader that does
   not work from `file:` URLs, and a larger surface to pin and to verify. Rejected for the single file.
6. **A CDN.** Excluded by the owner (no CDN): a reader's browser would contact a third party, the page would
   depend on its availability, and offline sites would not render.

## Decision

Option 1, and the rules below for this library and for any browser library that follows it.

### Rules for a vendored browser library

1. **In the repository, never from the network.** The file is a byte-identical copy of an upstream release
   artefact, in a directory of its own under the theme assets
   (`packages/doc/src/hecate/doc/theme/assets/<library>/`) that holds the file, the upstream `LICENSE` and a
   `VENDORED.md` (upstream, version, licence, what is bundled, and a `File | SHA-256` table). No page, script
   or stylesheet of the theme refers to a CDN or to any address outside the site; the diagram script makes no
   request of its own.
2. **Pinned.** One exact version and the SHA-256 of every file, in `VENDORED.md`. `check-licenses` re-computes
   the digests and fails on a missing or changed file, on a missing `LICENSE`, and on a directory not recorded in
   `THIRD_PARTY_NOTICES` (the rule that already covers the C sources of `json` and `http`).
3. **Recorded.** `THIRD_PARTY_NOTICES` names the library, its version, its source, its licence and the licences
   of the components bundled in it. The licence files that the upstream package ships are copied next to
   the file and are copied into every built site that holds the library.
4. **Loaded only where needed.** The renderer sets a flag on a page that holds a diagram
   (`RenderResult.diagrams`); only that page loads the library and its initialiser, as deferred scripts after the
   theme script. The files are written to the output only when at least one page needs them (`Theme.diagram_files`,
   separate from `Theme.asset_files`): a site without a diagram carries no byte of the library.
5. **Progressive enhancement.** The diagram source stays in the page as the code block that a ` ```mermaid ` fence
   already renders, escaped like every code block. The initialiser draws the diagram before it and hides the
   block; without JavaScript, with a failed render, or when the library is absent, the code block stays visible
   (after a short notice, when a render failed). Nothing in the build depends on the browser.
6. **Untrusted diagram text.**
   - Mermaid runs with `securityLevel: "strict"`: label text is encoded and the SVG is sanitised.
   - `htmlLabels: false`: labels are SVG text; no HTML from a diagram label reaches the page.
   - The `secure` list of the configuration includes `securityLevel`, `htmlLabels`, `theme`, `themeVariables`
     and `fontFamily` besides the defaults, so a `%%{init: ...}%%` directive or a front matter block inside a
     diagram cannot loosen the security level, change the theme or recolour the diagram.
   - The initialiser parses the SVG that the library returns as an XML document and imports its nodes; it never
     assigns markup (no `innerHTML`). A text of the diagram that would break the SVG is a failed render, shown as
     code.
   - The `maxTextSize` and `maxEdges` limits of the library stay at their defaults (50 000 characters, 500 edges).
7. **Content Security Policy and integrity.** The library is a same-origin classic script and needs no
   `unsafe-eval`; checked in Chromium on 2026-11-17 under `default-src 'self'; script-src 'self'`. The SVG
   that the library writes carries `style` elements and attributes, so a page that holds a diagram needs
   `style-src 'self' 'unsafe-inline'` (the theme itself needs none). A site that sets a stricter policy keeps the
   code blocks. No `integrity` attribute is written: the file is served from the same origin as the page, so a
   digest in the page would be as writable as the file; the digest that matters is the one that
   `check-licenses` verifies against the repository.
8. **Brand colours, light and dark.** The initialiser holds no colour. It reads the custom properties that the
   theme defines from the brand tokens (`--surface-100`, `--surface-200`, `--surface-300`, `--ink`, `--ink-muted`,
   `--border-strong`, `--earth`, `--on-earth`, `--danger`, and the site's own colour file when there is one) and
   gives them to Mermaid as the variables of its `base` theme, so the diagrams are drawn in the colours of the
   page. A diagram is drawn again when the reader switches the theme or the system preference changes. The
   stylesheet removes the drop shadows that Mermaid adds (brand: no shadows, no glows). Fonts are the
   brand sans-serif.
9. **Update procedure.** The owner decides to add a library (human gate; this ADR is that decision for Mermaid)
   and to move a pinned library to a new version. An agent prepares the update on a branch and the owner merges
   it: `npm pack mermaid@<version>` in an empty directory, copy of `dist/mermaid.min.js` and `LICENSE`, new
   `VENDORED.md` (version, digests, bundled components and their licences, re-checked), new
   `THIRD_PARTY_NOTICES` entry, `check-licenses`, then the rendering check below on the diagrams of the website
   (every page that holds a diagram, light and dark, no request outside the site). A major version is read
   for changes to the security configuration first.
10. **Another library** (for example a search engine or a chart) needs its own ADR: this one fixes the
    rules, not the choice.

### Where it lives

- `theme/assets/mermaid/` (`mermaid.min.js`, `LICENSE`, `VENDORED.md`), `theme/assets/mermaid-init.js`.
- Mermaid 12.3.0, SHA-256 `336df803d87a38b70a01e736e666c8f7601d2ce42f5e47c8fafe5d721074b9a3`.
- The renderer flag in `hecate.doc.markdown`, the page flag in `hecate.doc.site`, the two script elements in the
  theme layout, the strings `diagram`, `diagram_failed` and the `diagram_*` control labels in the interface strings. The initialiser
  also holds the navigation of a drawn diagram (toolbar, pan, zoom, full screen; owner request of 2026-11-18), as
  plain code under the rules above: no new library, no markup assigned, no request.

## Consequences

- Authors write a ` ```mermaid ` fence; the website's explanation pages can hold diagrams.
- A page with a diagram downloads 1.6 MB (gzipped, if the host compresses) once, and the browser caches it for the
  other pages of the site. A page without a diagram is unchanged.
- The repository grows by 5.5 MB per version of the library; a later update adds the new blob to history. The
  update procedure is the place to reconsider the ESM build or a smaller bundle if that weighs.
- Third-party code runs in the page of a reader. The strict level, SVG labels and the locked configuration
  reduce what a diagram text can do; they do not make the library as small as the theme scripts. A vulnerability
  in Mermaid or in a bundled component is handled as an update of the pinned version.
- The release artefacts of `hecate-doc` ship the file and its licence; the notices of the bundled components
  that the single minified file does not carry (everything but DOMPurify's) are listed in `VENDORED.md` and
  `THIRD_PARTY_NOTICES` by name and licence, not reproduced in full text. The owner decides whether that is
  enough for the release (OQ-34 asks the same for the fonts).
- Print and no-JavaScript readers see the source of the diagram.

## Verification

- `check-licenses` (CI): the directory has `LICENSE`, `VENDORED.md` and an entry in `THIRD_PARTY_NOTICES`;
  every digest of the table matches the file (unit tests in `tools/tests/licenses_test.lua`).
- `packages/doc/tests/unit/diagram_test.lua`: the renderer flags a mermaid fence and nothing else (including
  escaped mentions of the marker and raw HTML); the library and the initialiser are written and referenced only
  for a site and a page with a diagram, unmodified; the initialiser holds the strict configuration, no `innerHTML`,
  no colour literal, the brand tokens, and no request of its own.
- Manual check, recorded in `packages/doc/README.md` (Playwright and Chromium): build a page with diagrams,
  open it in the light and the dark theme, switch the theme, check that every diagram is drawn in the brand
  colours, that a malformed diagram stays a code block, that a directive cannot change the theme, and that no
  request leaves the site.
