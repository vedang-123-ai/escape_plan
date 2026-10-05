# S11.51 — Submission paperwork (tools list, description, answers, checklist)

- **Who:** agent-run (Claude Code), launched by Anish's orchestrator as agent B of 4
- **Date(s):** 2026-10-05
- **Status when I stopped:** `docs/tools-used.md` complete; `docs/submission/` drafted (4 files); every item needing a
  person is in `docs/submission/checklist.md` and BLOCKERS "S11.51 findings".

## What happened

- Read the official **2026 CAC Rules PDF** (linked from congressionalappchallenge.us/students/rules/). It settles
  several things the repo had wrong or did not know: the video is **1 to 3 minutes, max 3:00** (not 3:15); it must say
  each participant's name, the app name, a one-sentence purpose, the target audience and the tools and languages; it
  goes on **YouTube or Vimeo, public**; the form asks six named questions; the deadline is **12:00 pm EDT, Oct 26**;
  AI use must be fully disclosed and must not be "the entirety of the technical development"; judges may ask for the
  source code.
- `docs/tools-used.md` rewritten: Python versions from `requirements.lock`, licences read from each package's own
  metadata (installed the lock into a scratch venv), Apple frameworks from the actual `import` lines, Xcode/Swift from
  the local toolchain, Actions from `gate.yml`. Corrected: PDFKit is not used (`CGPDFDocument` is), Actions are v7 not
  v4/v5, duplicate Observation row merged, Hazard Hunt (cut) removed from the object-hazard row, accounts/sync/Mongo
  marked switched off. Added the AI disclosure with commit-trailer counts.
- `docs/submission/`: `app-description.md` (under 250 words), `what-we-learned.md`, `written-answers-draft.md` (the six
  rulebook questions first), `checklist.md`.
- Ran pitch-truth-auditor and doc-auditor; fixes listed in BLOCKERS "S11.51 findings".

## Decisions / surprises

- The repo is heavily AI-assisted: 513 of 634 non-merge commits carry a Claude co-author trailer. The rules allow AI
  with full disclosure, but expect "significant individual contributions". Only the team can write that sentence.
- The early framing really was firefighter-facing ("pre-incident intelligence", `archive/playbook-v1`
  `06-pivot-intro.md`), so "what we learned" says that rather than inventing a story.

## Questions for teammates

- @Anish: who exactly is on the entry (commit authors: vedang-123-ai, Anish, Yuki Tanaka)?
- @Anish: how will judges get the source code and a runnable app if they ask (private repo)?
- @team: each of you, one or two sentences on what you personally designed, built or checked.

## Next steps

S11.13: fix the script for the four required video items and the 3:00 limit, film, then paste the drafts after a
person reviews them.
