# `hecate-framework/hecate-setup`

The GitHub Action that installs the `hecate` executable of a release and puts it on the `PATH`.

```yaml
- uses: hecate-framework/hecate-setup@<tag>
  with:
    version: "0.4.0"
```

`hecate generate workflow ci` writes a workflow that uses it.

What it does: downloads `hecate-<version>-<os>-<architecture>.tar.gz` (a `.zip` on Windows) from the release
`v<version>` of `hecate-framework/hecate`, verifies it against the `.sha256` file of the release (the action fails
on a mismatch and installs nothing), unpacks it into the tool cache and adds the directory to the `PATH`. It runs on
Linux, macOS and Windows runners, X64 and ARM64.

| Input | Default | Meaning |
|---|---|---|
| `version` | required | the release, a SemVer version with no leading `v` |
| `repository` | `hecate-framework/hecate` | the repository whose releases carry the executable |

| Output | Meaning |
|---|---|
| `version` | the version installed |
| `path` | the directory that holds the executable |

This directory is the source; the repository `hecate-framework/hecate-setup` is a generated read-only mirror of it
(ADR 0017). Change it in the monorepo, never in the mirror.
