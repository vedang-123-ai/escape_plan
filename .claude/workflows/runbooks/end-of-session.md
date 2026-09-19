# End-of-session runbook

**Use when:** any playbook session (S11.1 to S11.13) is about to be declared DONE.

## Phase 1 — Verify

0. Confirm `git branch --show-current` is the session branch (never `main`) and that your diff touches only the
   session's OWNED FILES (`git diff --stat origin/main`).
1. Re-read the session file's acceptance criteria; verify each one against the repo with
   evidence (run the tests, open the artifact). Consider dispatching the `session-auditor`
   agent for an independent check.
2. If any criterion fails or is unverifiable, the session is NOT done — say so plainly.

## Phase 2 — Record

1. `docs/decisions.md`: add a row for every deviation from playbook defaults (what + why).
2. `docs/tools-used.md`: add any new library/API/tool with version, purpose, license
   (CAC originality requirement — non-negotiable).

## Phase 3 — Tracker (MANDATORY)

Root `CLAUDE.md`: **no note, no DONE.** This phase is not optional.

1. Write a session note in `docs/tracker/notes/` — copy `_TEMPLATE.md`, name it
   `YYYY-MM-DD-s<x>-<y>-<slug>.md`.
2. Update `docs/tracker/TODO.md` — remove only what genuinely passed, and add anything you
   discovered, each with a concrete next action. Leave device-only and key-blocked items in
   place with a note on what's needed. Never remove a line for something not actually observed.

## Phase 4 — Hand off

1. Produce the handoff artifact named in the session file (recording, screenshot, summary,
   committed files) and post it to the team.
2. Commit with a message referencing the session id.

## Done criteria

All four phases complete — including the Phase 3 tracker note/TODO.md. A session without a
handoff and a tracker note didn't happen. The `end-of-session-handoff` skill / `/handoff` command
runs this whole runbook.
