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
     "Next steps". Pick the oldest such pull request.
2. **Start.** Otherwise take the first unchecked item of `docs/roadmap.md` whose
   dependencies are done and which is not blocked: skip items needing a decision listed
   in `docs/open-questions.md` as `decision` or `spike → owner decision` that is not
   resolved, and items with an open issue labelled `needs-decision` or `blocked`.
3. **Nothing to do.** If every remaining item is blocked, open (or update) one issue
   labelled `needs-decision` listing what you are waiting for, then stop.

## 2. Claim it

- Branch `claude/relay-<roadmap-slug>`; create `HANDOFF.md` from
  `.github/relay/HANDOFF.template.md`, set `lock_until` to now + 90 minutes (UTC).
- Commit, push, open a **draft** pull request labelled `relay` and the relevant
  `package:*` labels, linking the roadmap item.

## 3. Work in small, pushed steps

- Follow `/implement-task` for the item, but split it into steps of at most ~30 minutes.
- After **each** step: update `HANDOFF.md` (done, next steps, decisions taken, open
  doubts, commands to re-run), refresh `lock_until`, commit and push. Never keep more
  than one step of unpushed work.
- Spikes end with a report and a recommendation; never decide in the owner's place.

## 4. Finish

- When the item meets the definition of done and CI is green on the three platforms:
  delete `HANDOFF.md`, tick the roadmap item, mark the pull request ready for review,
  and ask for the owner's review in a comment. Never merge.
- Stop after one roadmap item per run, even if usage seems to remain: the next run
  continues.
