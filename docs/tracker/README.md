# docs/tracker/ — team progress tracker & notes

The single place to see **what's done, what's unblocked, and who's on what** — without
re-reading the whole playbook. Three pieces:

| File | What it is | Who touches it |
|---|---|---|
| `checklist.md` | Master checklist: every session S0.1–S5.3 with checkboxes for acceptance criteria and end-of-session bookkeeping | Whoever finishes work checks boxes |
| `board.md` | The "right now" view: what's DONE, what each person can start today, what's blocked and on what | Update whenever a session flips to DONE |
| `notes/` | One markdown note per session (or per work day) — decisions made mid-flight, surprises, questions for teammates | Whoever did the work |

## How to use it (30 seconds)

1. **Starting work?** Open `board.md`, pick something from your "can start now" list,
   read the session file in `docs/playbook/S<x>-<y>.md` first (that's rule #1).
2. **While working**, jot anything worth remembering into a note:
   copy `notes/_TEMPLATE.md` → `notes/S<x>.<y>-<slug>.md` (e.g. `notes/S1.3-renderer.md`).
   Fragments are fine; this is a lab notebook, not documentation.
3. **Finishing a session?** In `checklist.md`, check off each acceptance criterion
   **only after you actually verified it** (run the test, watch the recording, click the thing).
   Then do the end-of-session boxes — they mirror the project protocol:
   decisions.md updated · tools-used.md updated · handoff artifact posted.
   A session with unchecked end-of-session boxes is NOT done, even if the code works.
4. Flip the session's status line in `checklist.md` and move it on `board.md`.
   That's what unblocks your teammates — do it immediately, not "later."

## Status vocabulary

- `DONE` — every acceptance box checked AND all three end-of-session boxes checked
- `IN PROGRESS (Px)` — someone is actively on it
- `READY` — all prerequisites DONE, nobody has picked it up
- `BLOCKED (needs S<x>.<y>)` — don't start; see rule #2 in CLAUDE.md
- `AT RISK / CUT CANDIDATE` — flagged per the cut order (S4.2 → S3.3 → S3.5 → camera tour → simplified agent)

## Conventions

- Checkboxes are the record; don't delete criteria you skipped — leave them unchecked and
  write why in a note. Overlap with `docs/decisions.md` is fine: decisions.md is the formal
  deviation log, notes/ is the informal scratchpad. When in doubt, note it here first and
  promote real deviations to decisions.md at session end.
- Dates: write them absolute (`2026-07-10`), never "yesterday."
- Claude Code (P3) reads this folder too — keeping it current means any session can be
  picked up by anyone (or by Claude) with zero re-explaining.
