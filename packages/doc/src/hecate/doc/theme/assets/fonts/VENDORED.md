# Vendored: fonts of the documentation theme (WOFF2, Latin subsets)

- Upstream: the npm packages `@fontsource/stix-two-text`, `@fontsource/fira-sans` and `@fontsource/fira-code`
  (Fontsource, MIT; the Latin subsets of the Google Fonts distribution of each family, in WOFF2), version 5.3.0 each.
- License: SIL Open Font License 1.1, one text per family (`OFL-stix-two-text.txt`, `OFL-fira-sans.txt`,
  `OFL-fira-code.txt`, each the unmodified `LICENSE` of its package). Recorded in THIRD_PARTY_NOTICES (section 1).
  Open question OQ-34 asks the owner to confirm that redistributing the subsetted files under their original names is
  acceptable.
- The files are the unmodified `files/<family>-latin-<weight>-<style>.woff2` of the packages, under the same names.
  The provenance was reconstructed on 2026-11-19 from the versions recorded in THIRD_PARTY_NOTICES: every file below
  is byte-identical to the file of the 5.3.0 tarball of its package.

| File | SHA-256 |
| --- | --- |
| `fira-code-latin-400-normal.woff2` | `6dc9da171ccea71d525379ee1cbf51d143e31acac330a251bb71b3d6060e687c` |
| `fira-code-latin-600-normal.woff2` | `53bd904d81c086b103b9e01ef84a98640b2124b78c789bb47ddabb4c41fc94b2` |
| `fira-sans-latin-400-normal.woff2` | `3e38d8c01fe97529fbf0a086bf958d724b723ca7fc8be77b4ba5745f6259b6ca` |
| `fira-sans-latin-500-normal.woff2` | `88d3e420adee3fa99ae50c15b123e3c9a07ce0ec0c03a01bd6bdd5232822da28` |
| `fira-sans-latin-600-normal.woff2` | `55e09735e30d8492afac5d59ac433c6b367bb7dd00c46e157cfe95c9fb29e833` |
| `stix-two-text-latin-400-italic.woff2` | `3d76ab92269582b8e11f3d969eaf93bb9609f1e08d5433fd18633e78e7900638` |
| `stix-two-text-latin-400-normal.woff2` | `65f8cdee99e0c883fa05a493812ad15fd93e3af5510276661e34c204f771e514` |
| `stix-two-text-latin-600-italic.woff2` | `57a8dc1f9c87ef6da140b88efb167827844a143088a43dd4abf5d11d7834da90` |
| `stix-two-text-latin-600-normal.woff2` | `c81c437a0d17a895f9d82f62611c1af238f04b0c996e6ef75c5441dd07769997` |
| `OFL-fira-code.txt` | `126cd7bf732b86f42885f1fbf682e6aeea456672c7fdb99f2d557ec44e468a28` |
| `OFL-fira-sans.txt` | `18aabf190848725e2576eefb5c29ba06aac1029d02132252a7f312eac2e50cf3` |
| `OFL-stix-two-text.txt` | `9d80d69f6a70033f4d113604bed4a3038b6e5b700c0266e7fe9f4033365ff076` |

## Provenance in the npm registry

Reproduce the files (in an empty directory, one package at a time; tarballs
`https://registry.npmjs.org/@fontsource/<family>/-/<family>-5.3.0.tgz`):

```sh
npm pack @fontsource/stix-two-text@5.3.0 @fontsource/fira-sans@5.3.0 @fontsource/fira-code@5.3.0
for archive in *.tgz; do mkdir "x-${archive%.tgz}" && tar -xzf "$archive" -C "x-${archive%.tgz}"; done
sha256sum x-*/package/files/*-latin-*.woff2 x-*/package/LICENSE
```

The values below are the `dist.integrity` and `dist.shasum` the registry publishes for each version
(`npm view @fontsource/<family>@5.3.0 dist.integrity dist.shasum`), recorded on 2026-11-19.
`lua tools/run.lua check-vendored --online` (nightly job `vendored`) downloads the tarballs again and verifies them.

| Package | Version | `dist.integrity` | `dist.shasum` |
| --- | --- | --- | --- |
| `@fontsource/fira-code` | `5.3.0` | `sha512-EJL968RJRkakubAj/coU8pSUaeTE5UNoRjtzAr6kGiSZ3jWuN8/AKWHwym/PFUaQL1q7IL/H+EXs4358YhrTBQ==` | `487475cedfa1f7ba7650810ddce00b6c7b1b7a25` |
| `@fontsource/fira-sans` | `5.3.0` | `sha512-z1SKSG7eRhm3srlb7rQ3j77QP4TP7OFxCZ4wUWhCdt+3hOF9K0AyvybpAsz6+JWNcCVV7AqC7dbOT3e67P2r5A==` | `b3c8f83028bf5a8b85792b50f2f0c65976e665cc` |
| `@fontsource/stix-two-text` | `5.3.0` | `sha512-/eVTBPvodwIlsUTImyGjNVG4wqi2SDi6nV0WmE0+ScfbCegC8zMkm6BER8dy8f900xgP1RkNx0HxjbixT/ISOg==` | `ea56772ec8e9be4461472c53d496199b21c0c7c9` |

| Vendored file | Package | Path in the package |
| --- | --- | --- |
| `fira-code-latin-400-normal.woff2` | `@fontsource/fira-code` | `files/fira-code-latin-400-normal.woff2` |
| `fira-code-latin-600-normal.woff2` | `@fontsource/fira-code` | `files/fira-code-latin-600-normal.woff2` |
| `OFL-fira-code.txt` | `@fontsource/fira-code` | `LICENSE` |
| `fira-sans-latin-400-normal.woff2` | `@fontsource/fira-sans` | `files/fira-sans-latin-400-normal.woff2` |
| `fira-sans-latin-500-normal.woff2` | `@fontsource/fira-sans` | `files/fira-sans-latin-500-normal.woff2` |
| `fira-sans-latin-600-normal.woff2` | `@fontsource/fira-sans` | `files/fira-sans-latin-600-normal.woff2` |
| `OFL-fira-sans.txt` | `@fontsource/fira-sans` | `LICENSE` |
| `stix-two-text-latin-400-italic.woff2` | `@fontsource/stix-two-text` | `files/stix-two-text-latin-400-italic.woff2` |
| `stix-two-text-latin-400-normal.woff2` | `@fontsource/stix-two-text` | `files/stix-two-text-latin-400-normal.woff2` |
| `stix-two-text-latin-600-italic.woff2` | `@fontsource/stix-two-text` | `files/stix-two-text-latin-600-italic.woff2` |
| `stix-two-text-latin-600-normal.woff2` | `@fontsource/stix-two-text` | `files/stix-two-text-latin-600-normal.woff2` |
| `OFL-stix-two-text.txt` | `@fontsource/stix-two-text` | `LICENSE` |
