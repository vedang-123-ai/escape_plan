# /session <session-id, e.g. S11.4>

Run a playbook session using the team's handoff protocol.

1. Map the id to its file: `S11.4` -> `docs/playbook/S11-4.md` (dot becomes dash). Read `CLAUDE.md`,
   that file, `docs/playbook/README.md` and `docs/tracker/BLOCKERS.md`.
2. **Branch first.** Run the session file's BRANCH block: `git fetch origin`, then
   `git switch -c s11-N-<slug> origin/main` (or a worktree). Confirm with `git branch --show-current`.
   Never work on `main`. If the branch already exists, switch to it and `git merge origin/main`.
3. Verify every prerequisite session is DONE (its note in `docs/tracker/notes/` and a merge on `origin/main`). If a
   prereq is not done, STOP and say so; never start a blocked session.
4. Show a short implementation plan before executing. Touch only the session's OWNED FILES.
5. Execute, following ACCEPTANCE exactly. Run the auditor agent the session names.
6. When done: verify every acceptance criterion with evidence, then run the `end-of-session-handoff` skill
   (BLOCKERS section, note, decisions.md, tools-used.md), `git fetch origin && git merge origin/main`, re-run
   ACCEPTANCE, and merge `--no-ff` to `main`.
