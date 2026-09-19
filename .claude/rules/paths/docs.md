---
description: Tracker, decisions log and tools-used conventions
globs: ["docs/tracker/**", "docs/decisions.md", "docs/tools-used.md", "docs/playbook/**"]
alwaysApply: false
---

# Docs rules (tracker, decisions, tools-used, playbook)

Status in this repo has contradicted itself before, and a decision entry once described files that were not
where it said. Docs are a mechanism, not a habit.

- **`BLOCKERS.md` is the board.** Anything not done, blocked or unverified goes there in the session you find it.
  Remove a line only when you personally verified it. Put your lines under **your session's own heading** so three
  people editing at once do not collide.
- **`TODO.md`** is the long-tail backlog only. When `TODO.md` and `BLOCKERS.md` disagree, `BLOCKERS.md` wins.
- **`decisions.md`** is newest-first and append-only; every deviation gets a dated row with the reason. Never edit an
  old row's meaning: correct it with a new row that says what it corrects (see the 2026-09-18 S8 correction).
  It merges with `merge=union`, so keep each entry on its own table row.
- **`activity-log.md`** is machine-written by the Stop hook. Do not hand-edit it.
- **`docs/tracker/notes/`**: one note per session, copied from `_TEMPLATE.md`, unique filename
  `<YYYY-MM-DD>-<slug>.md`. No note, no DONE.
- **`tools-used.md`**: every dependency, service and AI tool with version, purpose and licence. The Challenge
  requires it; finish it before submitting.
- **Verify before you write a status.** Test counts come from a run you did (`xcresulttool` for iOS), with the date
  and bundle name. Never copy a count forward.
- **Playbook files** describe work not yet done. Once a session ships, its file is deleted (history stays in git);
  the tag `archive/playbook-v1` holds the previous generation. Every session file keeps a BRANCH block and an
  OWNED FILES list; two sessions in the same lane must not own the same path.
- Do not write a doc that duplicates `CLAUDE.md`. Duplication is how docs drift.
