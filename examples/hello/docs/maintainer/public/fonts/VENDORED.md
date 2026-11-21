# Vendored: Inter (WOFF2, Latin subset), for the hello showcase

- Upstream: <https://github.com/rsms/inter> (the typeface), distributed as the npm package `@fontsource/inter`
  (Fontsource, MIT; the Latin subset of the Google Fonts distribution, in WOFF2).
- Version: 5.3.0
- License: SIL Open Font License 1.1 (text in `OFL-inter.txt`, the `LICENSE` of the package),
  Copyright 2016 The Inter Project Authors. Recorded in THIRD_PARTY_NOTICES (section 1b).
- The files are the unmodified `files/inter-latin-<weight>-normal.woff2` of the package, under the same names; the
  licence text is the unmodified `LICENSE` of the package. The documentation theme does not use them: the showcase
  loads them with its own `@font-face` (`hello-theme.css`).

| File | SHA-256 |
| --- | --- |
| `inter-latin-400-normal.woff2` | `8909904ab6c872eb994093482a88a28eca2cd95912d7b6fecd72103b0dc07edc` |
| `inter-latin-500-normal.woff2` | `f3779f1efccc4bdcdf9c0a02ab95bf6bd092ed09c48c08cedc725889edd1d19f` |
| `inter-latin-600-normal.woff2` | `f9a06e79cd3a2a20951c0f0e28f66dd0e6d3fda73911d640a2125c8fcb78f21a` |
| `OFL-inter.txt` | `3b0a5fca3d17942cde889069889dedbbbd075e9b599968c82a95f4d944e9b345` |

## Provenance in the npm registry

Reproduce the files (in an empty directory; tarball
`https://registry.npmjs.org/@fontsource/inter/-/inter-5.3.0.tgz`):

```sh
npm pack @fontsource/inter@5.3.0
tar -xzf inter-5.3.0.tgz
sha256sum package/files/inter-latin-400-normal.woff2 package/files/inter-latin-500-normal.woff2 \
  package/files/inter-latin-600-normal.woff2 package/LICENSE
```

The `integrity` and `shasum` that `npm pack` prints are the `dist.integrity` and `dist.shasum` the registry publishes
for the version (`npm view @fontsource/inter@5.3.0 dist.integrity dist.shasum`), recorded on 2026-11-19.
`lua tools/run.lua check-vendored --online` (nightly job `vendored`) downloads the tarball again and verifies them.

| Package | Version | `dist.integrity` | `dist.shasum` |
| --- | --- | --- | --- |
| `@fontsource/inter` | `5.3.0` | `sha512-RofMylZmjlJEfELXeNHFWBRcSs75rGU/6bV2S2jfnvv/3rPXPGe0LgUJTklcHZ9lM4OZmAVFhcJPnACfb91A3g==` | `866278dc2357659f8be1755c8b67f29d3697b440` |

| Vendored file | Package | Path in the package |
| --- | --- | --- |
| `inter-latin-400-normal.woff2` | `@fontsource/inter` | `files/inter-latin-400-normal.woff2` |
| `inter-latin-500-normal.woff2` | `@fontsource/inter` | `files/inter-latin-500-normal.woff2` |
| `inter-latin-600-normal.woff2` | `@fontsource/inter` | `files/inter-latin-600-normal.woff2` |
| `OFL-inter.txt` | `@fontsource/inter` | `LICENSE` |
