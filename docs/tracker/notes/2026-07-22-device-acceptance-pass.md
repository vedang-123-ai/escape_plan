# S2.2 / S2.3 / S3.4 / S3.5 — simulator device-acceptance pass

- **Who:** P3 (Claude)
- **Date(s):** 2026-07-22
- **Status when I stopped:** all four lanes walked click-by-click on a dedicated simulator;
  checklist/board updated for exactly what was watched happen. Evidence + demo b-roll in
  `artifacts/acceptance-2026-07-22/`.

## What happened

Setup: dedicated `p3-acceptance` iPhone 17 Pro simulator (iOS 26.5), app built into a private
`-derivedDataPath .build-p3`, fixtures (`twostory`, `apartment`) seeded straight into
`<data-container>/Documents/Homes/`, local backend (`uvicorn`, `BACKEND_BEARER_TOKEN=devtoken`,
port 8000) with `APIClient.baseURL`/`bearerToken` written via `simctl spawn defaults write`.
Interaction via **idb** HID events (new dev tool — added to tools-used.md); screenshots and
recordings via `simctl io`.

### Verified (watched on screen, evidence file per criterion)

- **S2.2 opening drag** — front door slid along its wall, width preserved
  (`s22-01/03`, `s22-02-drag-undo-redo.mp4`).
- **S2.2 undo/redo** — ~15 mixed ops (opening drags, room drags, 2× Add Room, Add Stairs)
  unwound with undo×8 to the pixel-identical original (`s22-18/19`); redo re-applied.
- **S2.2 stairs flow** — "Add Stairs" → "Add Stairs To…" sheet → Landing; commits + undoable
  (`s22-15/16/17`). Needed the workaround described under bugs.
- **S2.3 routes** — Kids' Bedroom primary as animated orange pulse out a green-highlighted
  exit + blue secondary window path; exploded view; camera tour recorded
  (`s23-04`, `s23-06`, `s23-05-tour-kids-bedroom.mp4`). Live POST /routes each time.
- **S2.3 badges** — apartment: red badges on all 5 rooms + "no second way out … depends on
  exit 'd_entry'" findings (`s23-09`); twostory kids' room correctly badge-free.
- **S3.4 switch (demo money shot)** — Everyone→Maya→Grandpa on twostory
  (`s34-02-profile-switch.mp4`): camera jumps to each profile's bedroom; Grandpa raises the
  red "No viable escape route" flag. One /routes POST per switch (backend log).
- **S3.4 CRUD** — added Grandpa (Elderly + Limited Mobility) and Maya (Child, Bedroom 2) via
  ProfilesScreen on Apartment 4B (`s34-05/06`).
- **S3.5** — breakdown legible incl. expanded per-item math + citation (`s35-01/02`);
  toggling one smoke-alarm item re-POSTed /score, score 75→77 on screen (`s35-05`).

### Still pending (NOT checked)

- S2.2 "fix a misplaced door on a real converted scan in <2 min" — needs S1.4/S1.5 real
  exports (drag mechanic itself verified).
- S2.2 stairs on a *hand-built* 2-story — verified on the seeded fixture only, and only via
  the workaround (bug 1 below).
- S2.3 real-device 60fps feel — simulator recording only.
- S3.4 "explanation text reflects the profile" — ANTHROPIC_API_KEY blocked (/explain).
- S3.3 live chat — key-blocked as before (not in this pass's scope).
- Anything needing real LiDAR hardware.

## Decisions / surprises

- **Session isolation** (promoted to decisions.md): another live session's `xctrunner` shared
  the default simulator and `.build-merge`, causing spontaneous shutdowns, wiped app data, and
  a different lane's build swapping in mid-pass. Dedicated device + private derived data fixed
  it — recommend this as standing practice for any on-simulator work.
- **idb over window-clicking**: CGEvent window clicks lose to whatever app holds focus; idb
  HID events need no focus. SwiftUI `Toggle`s only respond to knob-drag swipes, not taps.
- **Date-strategy bug confirmed from the consumer side**: pre-S4.1 build rejects ISO-date
  documents (`expected Double`), post-S4.1 build rejects Double-date documents
  (`expected String`) — matches the S4.1 fix writeup; raw schema fixtures work on current code.
- **UI bugs found for P2** (details in decisions.md): (1) toolbar doesn't re-render on
  tap-selection, so Add Stairs stays disabled until a revision-bumping action; (2) a redo tap
  right after undo was dropped once; (3) stale yellow selection marker until next commit.

## Questions for teammates

- @P2: bugs 1–3 above — want them as issues, or will you fold the
  selection-observability fix into your next editor pass?
- @P2: `scripts/s13-acceptance.sh` still drives `DollhouseDemoView` launch args that are no
  longer in navigation — retire or rewrite against the tab shell?
- @P1: S3.4's remaining box is /explain with profile context — bundle it into your
  ANTHROPIC_API_KEY live-run session.

## Next steps

1. P2 device session: real-device 60fps check (S1.3/S2.3) + the hand-built-home stairs pass.
2. P1 key session: S3.1/S3.2/S3.3 live runs + S3.4 explanation box.
3. Worktree 6 (S5.1): map `artifacts/acceptance-2026-07-22/` recordings to script beats —
  `s34-02-profile-switch.mp4` is the strongest candidate for the wow moment.
