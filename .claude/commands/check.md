---
description: Run every local quality gate and summarise
---

Run the local gates for: $ARGUMENTS (default: affected packages).

Use `lua tools/run.lua` tasks: format-check, lint,
typecheck, check-lua-constructs, check-boundaries, check-glossary, check-versions,
check-package-structure, check-adr-index, check-links, test. If a task does not exist
yet, say so and skip it. Summarise as a table: task, result, first error.
