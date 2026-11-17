# Vendored: mermaid (browser bundle)

- Upstream: <https://github.com/mermaid-js/mermaid>, npm package `mermaid`
- Version: 12.3.0 (`npm pack mermaid@12.3.0`, the `latest` dist-tag on 2026-11-17)
- License: MIT (see `LICENSE`), Copyright (c) 2014 - 2022 Knut Sveidqvist
- `mermaid.min.js` is the unmodified file `dist/mermaid.min.js` of the package (a single self-contained
  script, 5.5 MB, that defines the global `__esbuild_esm_mermaid_nm.mermaid`); `LICENSE` is the
  unmodified `LICENSE` of the package. ADR 0033 is the decision and the update procedure.
- Only the pages that hold a diagram load it (ADR 0033).
- Components bundled in `mermaid.min.js`, with the licence each declares on npm (checked on
  2026-11-17): `@braintree/sanitize-url`, `@iconify/utils`, `@upsetjs/venn.js`, `cytoscape`,
  `cytoscape-cose-bilkent`, `cytoscape-fcose`, `dagre-d3-es`, `dayjs`, `es-toolkit`, `katex`,
  `khroma`, `marked`, `roughjs`, `stylis`, `ts-dedent` and `@mermaid-js/parser` (MIT); `d3` (ISC);
  `d3-sankey` (BSD-3-Clause); `chevrotain` (Apache-2.0); `dompurify` (MPL-2.0 OR Apache-2.0, used
  under Apache-2.0; its notice stays in the file as a `@license` comment); `elkjs` (EPL-2.0 OR
  GPL-3.0-or-later, used under EPL-2.0, unmodified). No licence of a bundled component forbids
  redistribution of the unmodified file.

| File | SHA-256 |
| --- | --- |
| `mermaid.min.js` | `336df803d87a38b70a01e736e666c8f7601d2ce42f5e47c8fafe5d721074b9a3` |
| `LICENSE` | `ec9fb67dcb25eccc416ed56e1aab819222c805a2a4bfe4cb19e7556bf2ffde80` |
