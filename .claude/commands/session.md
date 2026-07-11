# /session <session-id, e.g. S1.2>

Run a playbook session using the team's handoff protocol.

1. Read `CLAUDE.md`, `docs/playbook/$ARGUMENTS.md` (note: file names use a dash, e.g. `S1-2.md`
   for S1.2), and `docs/decisions.md`.
2. Verify every prerequisite session is DONE (check decisions.md and the repo). If a prereq is
   not done, STOP and say so — never start a blocked session.
3. Create a short implementation plan for the session and show it before executing.
4. Execute, following the acceptance criteria exactly.
5. When done: verify each acceptance criterion explicitly, update `docs/decisions.md` with any
   deviations from playbook defaults, update `docs/tools-used.md` with any new dependencies,
   and write the handoff artifacts listed in the session file.
