# S11.5 — Readiness Home and the prevention layer

- **Who:** P3
- **Date(s):** 2026-09-23
- **Branch:** `s11-5-readiness-home` (worktree, cut from `origin/main`)
- **Status when I stopped:** All five mission items done and typechecked. Merged and
  re-verified against `origin/main` (no-op merge). **Not run on a simulator/device** — no
  simulator on this machine; every acceptance criterion I could clear without one is clear.

## What happened

**1. Readiness score/checklist stays first; Prevent, family plan, and homes now follow it
in the scroll**, per `01-product-spec.md` §2. `HomeScreen.checklistView` now renders, in
order: score header → critical → readiness card → scan-age caption (new) → stat tiles →
detailed checklist (with the reworked re-scan nudge) → **Prevent** (new) → **family plan**
(new) → **homes** (new, only shown once there's a choice — a single-home library already
names itself in the navigation title).

**2. Prevention tips.** `backend/corpus/prevention_tips.json` bundled byte-identical at
`escape_plan/Resources/prevention_tips.json`. `scripts/check-tips-sync.py` (stdlib-only)
diffs the two by bytes and reports the first differing line; verified exit 0, then a
deliberate one-character perturbation verified exit 1 with a useful message, then restored
(byte-identical again, confirmed with `diff`). The Home tab's "Prevent" section shows one
spotlighted tip per locked peril (`PreventionTipsFilter.spotlight`, deterministic — the
first `audience == .everyone` tip per peril, not a random pick), each with a tappable
"Source" button that reveals the corpus `cite` id. Every `PreventionTip` requires a
non-empty `cite` to decode at all, so there is no code path that can render a tip without
one.

**3. Scan freshness.** `ScanFreshness` (pure, Foundation-only) gives "scanned N days ago" /
"Built by hand — not yet scanned." text everywhere a home's readiness card shows, and a
re-scan nudge that fires on **either** of two triggers: the existing 180-day age threshold
(unchanged from what `HomeScreen.swift` already did before this session — just named and
tested now) **or** a wall added/removed since the last scan, whichever is more specific.
Wall count is a locally-persisted snapshot (`ScanFreshnessStore`, UserDefaults, the
`MeetingPointStore` precedent — no schema field), recorded when a scan is imported and
bootstrapped once for homes that predate the feature. Both reasons' copy says "resident-
maintained, not verified" — tested directly (`testNudgeMessagesAreHonestAboutResidentMaintenance`).

**4. `basis` label.** `ScoreScreen` now shows CODE-QUANTIFIED / GUIDANCE-BASED under each
peril sub-score (`ScoreBasisLabel`, mapping `ScoreBreakdown.basis`), plus a one-line caption
explaining the two tiers. Nil-safe throughout: a server predating S11.2 (no `basis` key), an
unrecognised peril, or an unrecognised value all render nothing rather than a guessed label.

**5. Onboarding copy.** The welcome step and the Home tab's empty state both now say "cited
prevention basics" before "readiness checklist" before "escape route" — checked the whole
tree first; neither string, nor anything else in `Onboarding/` or `Screens/`, claimed
firefighters use the app, so this was pure re-ordering, not walking back a claim.

**Testing.** New `escape_plan/Readiness/` (five files: `PreventionTip.swift`,
`PreventionTipsFilter.swift`, `ScanFreshness.swift`, `ScanFreshnessStore.swift`,
`ScoreBasisLabel.swift`) is Foundation-only and symlinked into
`tools/editorcore/Sources/EditorCore/Readiness` — no `Package.swift` edit needed. 33 new
tests across four files in `escape_planTests/EditorCore/Readiness*Tests.swift`. **EditorCore
516 → 549 passing, 0 failures** (verified before and after the merge with `origin/main`,
which was a no-op). `scripts/typecheck-ios.sh` **ok on all four targets** (`escape_plan`
debug + release, `escape_planTests`, `escape_planUITests`) at iOS 17.0, both before and after
the merge. `python3 scripts/check-tips-sync.py` exits 0.

**Disk:** `df -h /System/Volumes/Data` read 43GiB free before the first `swift test` and
43GiB free before the last one (156Gi/155Gi used both times — noise, not growth); no ENOSPC
anywhere this session. `tools/editorcore/.build` removed before finishing.

## Decisions / surprises

Both logged in `docs/decisions.md` (newest-first, 2026-09-23 rows):

- **The 180-day threshold is not new** — it's the number `HomeScreen.swift` already nudged
  at before this session (hardcoded, untested, no fallback). This session named it
  (`ScanFreshness.staleThresholdDays`), added the `meta.modified` fallback the mission asked
  for, and added the wall-edit trigger as a second, higher-priority reason. Nothing about
  the number itself changed.
- **`PreventionTip.cite` stays a single `String`.** `BLOCKERS.md:494` already flags a few
  composite/under-attributed tips and hands the "should `cite` become a list?" decision to
  this session. Ruling: no — that's a `backend/corpus/prevention_tips.json` +
  `validate.py` change, neither of which S11.5 owns. Carried forward below.
- **The family-plan meeting-point card is read-only**, opening the real editor
  (`Export/ExportPlanSheet.swift`, S11.6's file) rather than duplicating a second text field
  against the same `MeetingPointStore` UserDefaults key. Seemed like the safer call than
  guessing at an editing UI S11.6 is about to build anyway.
- **The homes section only renders when `library.homes.count > 1`.** A single-home library
  already names itself in the navigation title bar; a one-row "Homes" list under it would
  be pure repetition. Not logged in decisions.md — a small UI judgment call, not a deviation
  from a playbook default.
- The swift-scenekit-reviewer agent found **zero blocking issues** on the full diff. It
  independently re-verified: no forbidden imports in `Readiness/`, no model mutation outside
  the reducer, `Export/` untouched, no new/misused colours, all 44 real corpus tip citations
  resolve against `sources.json`, and the bundled copy is byte-identical. One cosmetic nit:
  the tappable source label shows the raw corpus id (e.g. `nfpa-escape-planning`) rather
  than a looked-up human title — not a citation-rule violation, just a rougher string than a
  title lookup would give. Left as-is; noted as a follow-up below.

## Questions for teammates

- **@S11.6** — your `ShareWithFireDepartmentCard` insertion point is
  `escape_plan/Screens/HomeScreen.swift:988`, inside `familyPlanSection(_ home: HomeModel)`,
  right after the `PracticeReminderCard` and before the closing of that `VStack`. At that
  point you have `home: HomeModel` in scope (so `home.id`, `home.name`, the full model for a
  snapshot), plus `library.store: HomeDocumentStore` and `apiClient` (environment) if your
  card needs either. I did not add any state var or sheet binding for your card — wire
  whatever presentation you need directly.
- **@S11.7** (SettingsScreen) — nothing here touches you; just flagging that the Home tab
  now opens `ExportPlanSheet` directly (previously only reachable from `BetaScreen`), in
  case your settings-driven entry point and this one should eventually converge on one
  presentation path.

## Next steps

Nothing left in my five mission items. Residual items are unverified-on-device or
explicitly out of this session's owned files — see the BLOCKERS block below.

---

## BLOCKERS block — paste into BLOCKERS.md

#### S11.5 · Readiness Home and the prevention layer (2026-09-23, branch `s11-5-readiness-home`)

Verified this session: EditorCore **516 → 549 passing, 0 failures** (33 new tests, all in
`escape_plan/Readiness/` + `escape_planTests/EditorCore/Readiness*Tests.swift`).
`scripts/typecheck-ios.sh` ok on all four targets at iOS 17.0. `python3
scripts/check-tips-sync.py` exits 0; verified the negative case too (a deliberate
perturbation of the bundled copy produces exit 1 with a useful message), then restored.
swift-scenekit-reviewer ran over the full diff: zero blocking findings. **`xcodebuild test`
NOT run — no simulator on this machine**, per the standing rule; nothing in this session was
verified on-device or in-simulator.

**Closed by this session:**

- [x] Home tab reframed: readiness score/checklist → Prevent → family plan → homes
      (`HomeScreen.swift`).
- [x] Prevention tips bundled and kept in sync (`escape_plan/Resources/prevention_tips.json`,
      `scripts/check-tips-sync.py`); every tip shows a tappable, citation-carrying source
      label; no tip can decode without a `cite`.
- [x] Scan freshness: age display with `meta.modified` fallback, plus a wall-edit trigger
      (`ScanFreshness`, `ScanFreshnessStore`), both honestly worded as resident-maintained.
- [x] `basis` (S11.2) rendered on `ScoreScreen`'s per-peril sub-scores — CODE-QUANTIFIED /
      GUIDANCE-BASED, nil-safe for a server predating the field.
- [x] Onboarding + empty-state copy leads with prevention/readiness; confirmed no string
      anywhere in `Onboarding/` or `Screens/` claims firefighters use the app.

**Found and NOT closed:**

- [ ] **Nothing in this session was verified on a simulator or device.** Every acceptance
      item above is typecheck- or unit-test-level. The new UI (`PreventionTipCard`,
      `scanAgeCaption`, the reworked `rescanNudge`, `meetingPointCard` opening
      `ExportPlanSheet`, `homesSection`) has never been rendered or tapped through. Next
      action: a device-acceptance pass (see the `device-acceptance` skill) once a simulator
      or a physical device is available — walk the Home tab end to end, confirm the Prevent
      cards, the scan-age caption, both re-scan-nudge wordings (stale vs. walls-edited, which
      needs a scanned home with a wall actually added/removed to trigger), and the meeting-
      point card opening the real export sheet.
- [ ] **`prevention_tips.json`'s composite/under-attributed tips are still under-attributed**
      (`BLOCKERS.md:494` — `tornado-pick-the-room-now`, `tornado-more-than-one-alert`).
      S11.5 ruled `cite` stays a single `String` (logged in `docs/decisions.md`,
      2026-09-23) because fixing this is a `backend/corpus/prevention_tips.json` +
      `backend/corpus/validate.py` change, neither of which this session owns. Next action:
      whoever next owns the corpus decides whether `cite` becomes a list (and updates
      `validate.py` check 7 to accept both shapes) or the two tips get split into
      single-source tips instead.
- [ ] **The "Source" tap in `PreventionTipCard` shows the raw corpus id** (e.g.
      `nfpa-escape-planning`), not a looked-up title/org. Not a citation-rule violation — the
      id resolves server-side and nothing false is shown — but a rougher string than a
      `sources.json` title lookup would give. Flagged by swift-scenekit-reviewer as a
      cosmetic nit, not a blocker. Next action: whoever next touches this card, or bundles
      `sources.json` client-side for another reason, can upgrade it then.
- [ ] **The "walls changed" nudge trigger has no end-to-end verification.** Unit-tested at
      the `ScanFreshness`/`ScanFreshnessStore` level (33 new tests), but the full path —
      scan a home, edit a wall in the editor, return to Home, see the nudge — has never run,
      because it needs both a simulator (blocked above) and a real RoomPlan scan or an
      editor session. Next action: part of the device-acceptance pass above.
