---
description: Full review of one package by the relevant specialist agents
---

Review the package: $ARGUMENTS

Run, in this order, and collect findings:
1. `pkg-<name>`: conformance to its specification, README and invariants.
2. `architect`: boundaries and decisions.
3. `api-reviewer` and `dx-reviewer`: public API.
4. `terminology-reviewer`: vocabulary.
5. `test-engineer`: coverage of invariants and edge cases.
6. If the package has C code: `native-code-reviewer`. If it parses untrusted input or
   handles credentials: `security-reviewer`. If platform-dependent:
   `cross-platform-reviewer`. If on a hot path: `performance-engineer`.

Output one consolidated report ordered by severity, with file:line references and a
proposed fix for each finding. Do not modify code unless asked.
