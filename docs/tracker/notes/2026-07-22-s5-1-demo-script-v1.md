# S5.1 — Demo script + storyboard v1

- **Who:** P3
- **Date(s):** 2026-07-22
- **Status when I stopped:** script-v1 + storyboard-v1 delivered in `docs/demo/`; v0 files
  marked superseded (kept). Acceptance NOT self-checked — both boxes need humans.

## What happened

- Promoted the 2026-07-16 v0 draft to a working v1 against the real 2026-07-22 build state.
  Most `[PENDING]` tags resolved to true-now (S2.1–S2.3, S3.2–S3.5 all code-done); what's
  still pending is split into `[PENDING: session]` (feature) vs `[FOOTAGE]` (capture).
- **VO: 436 words ≈ 2:54 at 150 wpm** — ~21s under the 3:15 gate. Only two statistics, both
  cited (`redcross-two-minutes`, `redcross-escape-fact-sheet`); grepped both ids against
  `sources.json`, and `backend/corpus/validate.py` passes (11 sources, 6 files, thresholds
  consistent).
- Added a **truth-ledger appendix**: all 17 spoken claims → status → evidence
  (file/test/decisions.md entry), plus production caveats (no key on Render, cold-start
  warm-up, editor containment gap).
- **storyboard-v1 defines the canonical b-roll path contract** — 13 named paths under
  `docs/demo/broll/` (e.g. `s23-routes-dollhouse.mov`, `s34-profile-switch.mov`) with capture
  standards (landscape, clean, one take, twostory fixture) so concurrent capture lanes can
  deliver without coordination. Interim storage rule until P1 decides git-vs-drive:
  ≤30s/≤50 MB per take, or drive + committed `INDEX.md`.

## Decisions / surprises

- Ran ahead of the S4.1 prereq by explicit direction — logged in decisions.md (second
  instance of the approved 2026-07-16 deviation).
- Beat 2's "eighty percent" is gone → "most of the way there" (never had a source).
- Beat 5 locked to build semantics: the kids'-room finding is the **too-small window** via
  the agent's `check_egress` (0.4 m < 0.508 m) — the engine's `no_secondary_egress` does NOT
  trip there; profile switch on camera is **mobility_limited/elderly only** (child is a
  tested no-op). Both were easy overclaims a judge could catch.
- Surprise from recon: no b-roll worktree plan or `docs/demo/broll/` existed in the repo —
  the storyboard is now the contract those captures land against.

## Questions for teammates

- @P1: tech-accuracy pass on script-v1 (esp. truth-ledger rows 10–11) — that's acceptance
  box 2. Also: b-roll storage decision (git vs drive+INDEX) before the first `.mov` lands.
- @P1+@P2+@P3: schedule the table-read (acceptance box 1). Read aloud, time it.
- @P2: when recording device sessions, use the canonical paths in storyboard-v1 §b-roll
  contract; `s14-roomplan-capture.mov` is the one take that can't be redone late.

## Next steps

Table-read + P1 pass → check the two acceptance boxes → S5.1 DONE. Re-read the script once
S4.1's golden path actually runs (and update Beat 6 if S4.2 drill is cut — delete, don't
soften). S5.2 unblocks on those boxes.
