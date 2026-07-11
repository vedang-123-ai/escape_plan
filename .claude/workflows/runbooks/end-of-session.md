# End-of-session runbook

**Use when:** any playbook session (S0.1–S5.3) is about to be declared DONE.

## Phase 1 — Verify

1. Re-read the session file's acceptance criteria; verify each one against the repo with
   evidence (run the tests, open the artifact). Consider dispatching the `session-auditor`
   agent for an independent check.
2. If any criterion fails or is unverifiable, the session is NOT done — say so plainly.

## Phase 2 — Record

1. `docs/decisions.md`: add a row for every deviation from playbook defaults (what + why).
2. `docs/tools-used.md`: add any new library/API/tool with version, purpose, license
   (CAC originality requirement — non-negotiable).

## Phase 3 — Hand off

1. Produce the handoff artifact named in the session file (recording, screenshot, summary,
   committed files) and post it to the team.
2. Commit with a message referencing the session id.

## Done criteria

All three phases complete. A session without a handoff didn't happen.
