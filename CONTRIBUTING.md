# Contributing to Hecate

Thank you for your interest. Hecate is at the specification stage; contributions to
the design are as welcome as code.

## Before writing code

- Read [docs/vision.md](docs/vision.md) and [docs/glossary.md](docs/glossary.md).
- Check the [roadmap](docs/roadmap.md) and the relevant
  [architecture specification](docs/architecture/).
- Significant design changes require an Architecture Decision Record
  (see [docs/adr/README.md](docs/adr/README.md)).

## Conventions

- Lua 5.5, no implicit globals, LuaLS annotations on every public API.
- Coding standards: [docs/architecture/coding-standards.md](docs/architecture/coding-standards.md).
- Commits: [Conventional Commits](https://www.conventionalcommits.org/), scoped by
  package (`feat(http): ...`).
- Every pull request updates tests, reference documentation and the changelog.

## Documentation translations

The website source is written in English. Translations live under
`website/<locale>/` and follow the process described in
[docs/architecture/documentation.md](docs/architecture/documentation.md).
