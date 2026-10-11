# Mirror template

Files in this directory are injected into every read-only mirror
(`<org>/hecate-<name>`) by the `split` task (ADR 0017). They are not used by the
monorepo itself.

- `READ-ONLY.md`: notice placed at the mirror root.
- `.github/workflows/close-pull-requests.yml`: closes pull requests opened on a mirror.

`{{package}}`, `{{rock}}` and `{{org}}` are substituted by `split`.
