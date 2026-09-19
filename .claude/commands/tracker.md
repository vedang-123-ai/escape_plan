# /tracker

Report project status from the tracker. Do not guess; read the files.

1. Read `docs/tracker/BLOCKERS.md` first (the ranked board), then `docs/tracker/TODO.md`, then
   `git fetch origin && git log --oneline main..origin/main | head` to see what teammates merged.
2. Summarize, grouped:
   - **DONE** - sessions fully complete (merged, note written, acceptance verified).
   - **CODE DONE, needs verification** - split into **device-blocked** (needs the simulator or phone) and
     **key-blocked** (needs a funded `ANTHROPIC_API_KEY`).
   - **READY** - prerequisites met, not started (use the lane table in `docs/playbook/README.md`).
   - **BLOCKED** - and on what.
3. Call out the critical path to the Oct 5 end-to-end demo milestone and the Oct 24 submission, and anything at risk.

Keep it skimmable. This is a read-only report; do not change any files.
