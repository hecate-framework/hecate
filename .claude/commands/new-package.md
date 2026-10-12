---
description: Scaffold a new Hecate package with all context files
---

Create the package: $ARGUMENTS

1. Check with the `architect` agent that the package fits the layers in
   `docs/architecture/overview.md`; draft an ADR if it introduces a new layer or a
   third-party dependency.
2. Create `packages/<name>/` with `README.md` and `CLAUDE.md` following an existing
   package (e.g. `packages/router`) as the template, and the directories described in
   `docs/architecture/coding-standards.md`.
3. Create `.claude/agents/pkg-<name>.md` following an existing package agent.
4. Add the package to `packages/README.md`, `docs/architecture/overview.md` (graph),
   `docs/roadmap.md`, the README components table and `llms.txt`.
5. Prefer `lua tools/run.lua new-package <name> --layer "<label>" --phase <n> --summary "<text>" [--deps a,b]` (scaffolds files, agent, catalogue, graph and `llms.txt`) and verify its output.
