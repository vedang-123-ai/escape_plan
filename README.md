# Escape Plan

Congressional App Challenge 2026 — iOS app that 3D-models your home (LiDAR scan + full editor) and computes personalized, animated fire escape routes, with a grounded AI safety inspector. See `CLAUDE.md` for the full project brief.

## How we work

1. Work is split into checkpointed sessions — see `docs/playbook/` (one file per session, with owner, prereqs, acceptance criteria).
2. Before starting a session: read `CLAUDE.md`, the session file, and `docs/decisions.md`. Never start a session whose prereqs aren't done.
3. A session is done only when its acceptance criteria pass.
4. Every session ends by updating `docs/decisions.md` + `docs/tools-used.md` and posting the handoff artifact.
5. Lanes: P1 = backend/ML/routing · P2 = iOS/3D · P3 = Claude Code (corpus, backend scaffold, persistence, chat, profiles, score, drill, video script).
