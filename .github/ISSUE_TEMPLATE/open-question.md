---
name: Open question
about: Record an open question (a decision, a research task, a spike or a known limitation)
labels: open-question
---

<!--
`docs/open-questions.md` is the source of truth for open questions. Open this issue to discuss and
track one; the matching entry of the file gets the next free OQ number and links here. Title:
`OQ-<n>: <short title>`. Labels: `open-question`, one `oq:<type>`, the `package:*` labels, and one
`due:*` label (the phase before whose end the question must be resolved, `due:none` if it blocks
nothing). Never use `needs-decision` or `blocked`: the relay reads them as a blocked roadmap item.
Write each section as short prose or a table, not as a long list.
-->

**ID:** OQ-
**Type:** decision | research | spike | limitation
**Package(s):**
**Blocks:** <!-- roadmap items or phases that cannot be finished without the answer -->
**Resolve before:** <!-- the roadmap item or gate where it becomes a problem, and why (what breaks or is redone if it stays open) -->
**Status:** open

## Question

<!-- What must be decided, in one or two sentences, then the points to settle. -->

## Context

<!-- Specifications, ADRs, reviews, code; what is known and what was measured. -->

## Options and recommendation

<!-- One row per option: what it costs, what it breaks, which one you recommend. A table is welcome. -->

## Conservative default meanwhile

<!-- What is implemented if nothing is decided. -->
