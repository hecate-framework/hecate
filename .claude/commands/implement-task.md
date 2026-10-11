---
description: Implement a roadmap item end to end
---

Implement the roadmap item: $ARGUMENTS

1. Locate the item in `docs/roadmap.md` and identify the packages involved.
2. Read, in this order: the ADRs referenced by those packages, the relevant
   `docs/architecture/*.md` specification, each `packages/<name>/README.md`,
   and `docs/glossary.md`.
3. List any decision the item requires that is not recorded. For each, either draft a
   `Proposed` ADR or add an entry to `docs/open-questions.md`. Stop and report if a
   missing decision would change the public API in a way that is hard to revert.
4. Write tests for the public behaviour first, then implement.
5. Run the formatter, linter, type checker and the test suite of the affected packages.
6. Update the package README, the reference docs in `website/`, `CHANGELOG.md`, and
   tick the roadmap item.
7. Summarise what was done, what was decided, and what remains open.
