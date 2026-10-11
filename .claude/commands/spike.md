---
description: Time-boxed research answering an open question
---

Run a spike on: $ARGUMENTS

1. Find the question in `docs/open-questions.md` (or add it).
2. Investigate with minimal throwaway code under `spikes/<id>/` (git-ignored except the
   report). Prefer primary sources: official docs, specifications, source code.
3. Write `docs/spikes/<OQ-id>-<slug>.md`: question, method, findings (with versions and
   platforms tested), recommendation, remaining risks.
4. Update the open question with a link and, for decisions, draft a `Proposed` ADR.
   Do not mark anything `Accepted`.
