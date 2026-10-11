# 0013 — English in the repository, multilingual public documentation

- **Status:** Accepted
- **Date:** 2026-10-11
- **Deciders:** project owner
- **Packages:** all, website
- **Related:** [documentation.md](../architecture/documentation.md)

## Decision

- Code, comments, annotations, error messages, logs, commit messages, engineering
  documentation (`docs/`) and agent definitions: **English**.
- Public website: English source; translations under `website/<locale>/`; French is the
  first translation. Further locales by contribution.
- Error messages are not translated at run time (stable, searchable); the website
  documents each error code.

## Verification

`check-translations` reports missing or stale translated pages (source page newer than
translation).
