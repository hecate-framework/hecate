---
description: One unit of autonomous, resumable work (used by the relay routine)
---

You are running the Hecate **relay**: autonomous work split into units that survive any
interruption (usage limit, idle VM reclaimed, timeout). You cannot know how much usage
remains, so assume you may be stopped at any moment and keep the repository resumable
at all times. Specification: `docs/architecture/ai-assisted-development.md#relay`.

## 1. Find what to do (in this order)

1. **Resume.** List open pull requests labelled `relay` (`gh pr list --label relay`).
   For each, read `HANDOFF.md` at the root of its branch.
   - If `lock_until` is in the future, another run owns it: skip it.
   - If CI failed or `status: in-progress`, check out the branch and continue from
     "Next steps". Pick the oldest such pull request. **Push to that pull request's own
     branch**, even when the session designates another one: never redo its work on a
     session branch.
2. **Start.** Otherwise take the first unchecked item of `docs/roadmap.md` whose
   dependencies are done and which is not blocked. A **phase gate** item is startable only
   when every other item of its phase is ticked, and no item of phase N+1 is startable
   while the gate of phase N is unticked (see "Phase gates" below). Skip items needing a
   decision listed in `docs/open-questions.md` as `decision` or `spike → owner decision`
   that is not resolved, and items with an open issue labelled `needs-decision` or `blocked`.
3. **Nothing to do.** If every remaining item is blocked, open (or update) one issue
   labelled `needs-decision` listing what you are waiting for, then stop.

## 2. Claim it

- Branch `claude/relay-<roadmap-slug>`; create `HANDOFF.md` from
  `.github/relay/HANDOFF.template.md`, set `lock_until` to now + 90 minutes (UTC).
- Commit, push, open a **draft** pull request labelled `relay` and the relevant
  `package:*` labels, linking the roadmap item.

## 3. Work in small, pushed steps

- Follow `/implement-task` for the item, but split it into steps of at most ~30 minutes.
- Before **each** push (agents you delegate to included, name it in their brief): `lua tools/run.lua setup-luals`
  once per session, then `lua tools/run.lua typecheck` (it finds the LuaLS under `spikes/luals`). CI fails on
  every typecheck warning; never push without it, and never accept a report that says it was not run.
- Keep `HANDOFF.md` tidy: "Next steps" lists only open work; when a step is finished, move it to "Done" (with its commit) and remove it from "Next steps", never leave a `DONE` line there.
- After **each** step: update `HANDOFF.md` (done, next steps, decisions taken, open
  doubts, commands to re-run), refresh `lock_until`, commit and push. Never keep more
  than one step of unpushed work.
- Spikes end with a report and a recommendation; never decide in the owner's place.
- When you add an open question to `docs/open-questions.md`, also open its mirror issue from the template
  `.github/ISSUE_TEMPLATE/open-question.md`: title `OQ-<n>: <short title>`, labels `open-question`,
  `oq:<type>`, `due:phase-N` (or `due:none`) and the `package:*` labels. The body **must** follow the template: read
  `.github/ISSUE_TEMPLATE/open-question.md` before creating the issue (issue tools never apply a template, so a body written
  from memory is wrong), keep all its headings in order (**ID**, **Type**, **Package(s)**, **Blocks**, **Resolve before**,
  **Status**, `## Question`, `## Context`, `## Options and recommendation`, `## Conservative default meanwhile`), fill every
  one from the entry (write `none` where it has nothing, never drop a heading), and drop only the HTML comments. After
  creating it, read the issue back and fix the body if a heading is missing. Never label it
  `needs-decision` or `blocked` (the relay reads those as a blocked roadmap item). The file stays the source of
  truth. When an entry is resolved, record only the final answer in the file and close its issue with a link
  to the pull request.
- Build and run third-party code only inside the repository, under
  `spikes/<OQ-id>/` (git-ignored), never in `/tmp`. One command per call, no
  `cd … &&` chains, so the repository's permission rules apply. For example:
  `git clone --recursive https://github.com/luvit/luv spikes/OQ-1/luv`, then
  `cmake -S spikes/OQ-1/luv -B spikes/OQ-1/build -DLUA_INCLUDE_DIR=/opt/lua-5.5/include`,
  then `cmake --build spikes/OQ-1/build`.
- If a command is denied, do not retry variants: record the exact command and the
  denial in `HANDOFF.md`, push, and stop.

## 4. Finish

- When the item meets the definition of done and CI is green on the three platforms:
  delete `HANDOFF.md`, tick the roadmap item, mark the pull request ready for review,
  and ask for the owner's review in a comment. Never merge.
- Stop after one roadmap item per run, even if usage seems to remain: the next run
  continues.

## 5. Phase gates

A gate item (`docs/roadmap.md`, "Phase gates") is a verification, not development. It follows the
same claim and handoff steps (branch `claude/relay-phase-<n>-gate`, draft pull request, `HANDOFF.md`),
and its steps are the four checks of the roadmap: completeness, it works, coherence, open questions.

- Verify from a clean checkout, not from memory: run the tools, build the native modules, read the
  code of every ticked item against its specification and the definition of done, run the
  examples and benchmark scenarios, read the CI results of the latest `main` on the three
  platforms. Use the reviewer agents (`/review-package`) on the packages of the phase.
- Write the report `docs/reviews/phase-<n>.md`: for each ticked item, the evidence that it is
  delivered and works (command, result, file), then the gaps found, then the open questions
  with their context and a recommendation.
- Triage every minor finding yourself, never by asking the owner (owner instruction, 2026-11-01): *does this minor
  belong to an item that must be resolved by the end of this gate?* If yes (a defect of something the phase delivered),
  fix it in the gate's pull request, test first. If no (it needs a measurement or a later phase to be judged, such as
  a performance finding, or it is a deliberate limit), defer it: write it into the roadmap item of the later phase that
  will handle it, with a pointer to the review row and what to check, or record it as a known limitation in
  `docs/open-questions.md`, so it is not forgotten. Give each row of the review its disposition (fixed with the
  commit, or deferred to which item). Never edit an Accepted ADR; make an undecided choice conservatively and record
  it in `docs/open-questions.md` for confirmation. Use one specialist agent per package for the fixes, and run
  `typecheck` (`lua tools/run.lua setup-luals` installs the pinned LuaLS under `spikes/`, checking its sha256)
  before pushing.
- Fix a small gap in the pull request. Add a larger one as a new unticked roadmap item placed
  before the gate, and stop: the gate stays unticked.
- Put the open questions to the owner: update `docs/open-questions.md` and open (or update)
  one issue labelled `needs-decision`. Never decide them.
- Tick the gate only when the report shows no open gap and each listed question has an owner
  decision or a recorded deferral; then follow "Finish" above.
