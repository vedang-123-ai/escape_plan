# Working protocol

Work is organized into checkpointed sessions S0.1–S5.3 (`docs/playbook/S<x>-<y>.md`), each with
an owner, prerequisites, acceptance criteria, and a handoff artifact. Dependency map:
`docs/playbook/03-sessions-intro.md`.

## Session rules

1. Read `CLAUDE.md`, the session file, and `docs/decisions.md` before starting. `/session <id>`
   does this for you.
2. Never start a session whose prerequisites aren't DONE.
3. A session is DONE only when every acceptance criterion passes.
4. Every session ends with: acceptance verified, `docs/decisions.md` updated (any deviation
   from playbook defaults, with why), `docs/tools-used.md` updated (any new dependency — CAC
   originality requirement), handoff artifact posted. A session without a handoff didn't happen.

## Schedule pressure

Deadline: submit by Oct 24, 2026; end-to-end demo path must work by Oct 5. If behind, cut in
this order: S4.2 drill → S3.3 chat → S3.5 score → camera tour → simplified agent.
Never cut scan → editor → 3D routes → profile switch.

## Validation commands (grow this list as modules land)

- Corpus: `python3 backend/corpus/validate.py`
- Backend (once S1.6 lands): `python3 -m pytest backend/tests/`
