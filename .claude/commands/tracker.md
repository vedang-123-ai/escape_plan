# /tracker

Report project status from the tracker. Do not guess — read the files.

1. Read `docs/tracker/board.md` and `docs/tracker/checklist.md`.
2. Summarize, grouped:
   - **DONE** — sessions fully complete (including device/human steps).
   - **CODE DONE — needs verification** — code + tests pass, but an acceptance step remains.
     Split these into **device-blocked** (needs a simulator/phone) vs **key-blocked** (needs
     `ANTHROPIC_API_KEY` on Render).
   - **READY** — prerequisites met, not started.
   - **BLOCKED** — and on what.
3. Call out the critical path to the Oct 5 end-to-end demo milestone and anything at risk.

Keep it skimmable. This is a read-only report — don't change any files.
