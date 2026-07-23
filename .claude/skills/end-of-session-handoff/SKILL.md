---
name: end-of-session-handoff
description: Run the complete mandatory end-of-session protocol for a playbook session (S0.1–S5.3). Use when finishing/closing a session, declaring one DONE, or when the user says "wrap up", "hand off", "close out S<x>.<y>". This is the authoritative protocol — the tracker step is MANDATORY.
---

# end-of-session-handoff

Root `CLAUDE.md` is explicit: **a session without a handoff AND a tracker note didn't happen.**
Do all of the following before calling any session DONE. Skipping the tracker note is the most
common miss — it is NOT optional.

## 1. Verify acceptance (evidence, not claims)

Re-read the session file's acceptance criteria (`docs/playbook/S<x>-<y>.md`). Verify each against
the repo — run the tests (invoke the `verify-all` skill), open the artifact. Consider dispatching
the `session-auditor` agent for an independent check. Any criterion that fails or is unverifiable
→ the session is NOT done; say so plainly.

**Device-only criteria stay unchecked** unless a human actually watched it on hardware. Code +
unit tests passing ≠ a device-acceptance box checked.

## 2. Record deviations & tools

- `docs/decisions.md` — add a row for every deviation from playbook defaults (what + why).
- `docs/tools-used.md` — add any new library/API/tool with version + purpose (CAC originality
  requirement, non-negotiable). If none, no change needed.

## 3. Tracker (MANDATORY — the step the old runbook omitted)

- Write a session note in `docs/tracker/notes/` — copy `_TEMPLATE.md`, name it
  `YYYY-MM-DD-s<x>-<y>-<slug>.md`. Fragments are fine; capture what happened, surprises, and the
  next step.
- Update `docs/tracker/TODO.md` — remove only the lines that genuinely passed, and add anything
  you discovered, each with a concrete next action. Leave device-only and key-blocked items in
  place with a note on what's needed. Refresh the `_Last verified:_` stamp at the top.

## 4. Hand off & commit

- Produce the handoff artifact named in the session file (recording, screenshot, summary, files).
- Commit with the session id in the message. Branch first if on `main` and the change is
  substantial. Do not push unless asked.

## Done criteria

Acceptance verified + decisions/tools recorded + **tracker note & board & checklist updated** +
handoff artifact + commit. All five. No note, no DONE.
