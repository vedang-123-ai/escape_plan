# 02 · Frontend (iOS app)

Canonical home for AUD-013, AUD-014, AUD-017, AUD-019, AUD-033. The iOS app is the only frontend.

## Overview

- **State:** `ContentView` owns one `HomeLibrary` (ObservableObject over the Homes directory), one `ReadinessStore`
  (active home, `/score` result, checklist done-state) and one `AppRouter` (tab + cross-tab requests). `HouseScreen`,
  `DrillScreen`, `ProfilesScreen` and `BuildFromPlanView` each build **their own** `HomeDocumentStore` and, where they
  edit, their own `HomeModelStore`.
- **Navigation:** 5 tabs. Home pushes Score and Drill; Home's "+" menu opens Scan, Build Manually (pushes a new
  `HouseScreen`) and Import Plan (`BuildFromPlanView` sheet). House is always the active home. Settings holds server,
  account, fire-department sharing.
- **Networking:** `APIClient` + per-endpoint extensions, all through `session`; one failure classifier
  (`BackendFailure`). Timeouts: 90 s (`/routes`, `/score`, `/convert`, `/diff_obstructions`, `/evacuate`, `/analyze`),
  180 s (`/build`), **60 s (`/chat`)**.
- **Verified today:** `scripts/typecheck-ios.sh` ok on all four targets (177 app files Debug + Release, 86 unit-test
  files, 10 UI-test files); full simulator suite **987 tests: 972 passed, 7 failed, 8 skipped** (see 11_TESTING).

Screen-level functional gaps (Profiles unreachable, no home delete, analyze/explain unwired, AI draft not reviewed)
are in `14_FEATURE_COMPLETENESS.md` (AUD-020 … AUD-023).

---

### [AUD-013] The House editor keeps a stale copy of the home and overwrites other screens' writes

**Severity:** P1
**Location:**
- `escape_plan/Screens/HouseScreen.swift:2226-2271` (`loadIfNeeded` — `guard session == nil` — loads once per view lifetime)
- `escape_plan/Screens/HouseScreen.swift:244-265` (`onDisappear` → `unregisterFromLibrary()` clears `library.editor`
  and `syncRepository.openHomeID`; nothing re-registers on re-appear)
- `escape_plan/Screens/HouseScreen.swift:2288-2296` (`autosave` writes the whole in-memory model)
- Other writers of the same file: `HomeScreen.swift:84-91` (re-scan diff "Add to Home"), `Onboarding/OnboardingState.swift:106`,
  `Persistence/HomeDocumentSyncRepository.swift:97-121` (sync pulls), `ProfilesScreen.swift:226-234` (currently unreachable)
- `escape_plan/ContentView.swift:137-154` (`HouseTab` is only rebuilt when the active home id or a house request token changes)

**Category:** frontend / data integrity
**What I found:** `HouseTab` lives inside a `TabView`, so its `HouseScreen` and its `EditorSession` survive tab switches.
The session is loaded from disk exactly once. Other screens write the same `Documents/Homes/<id>.homeplan.json`
without telling it. The next commit in House (any drag, rename, add) autosaves the stale model over those writes.

**Current behavior (code-traced; not reproduced on a simulator):**
1. User opens House (active home X loads). Switches to Home, runs "Re-check a room", taps "Add to Home" on a found
   object → file X now has the object. Back in House, the object is not shown; the next edit writes X without it. The
   object is gone.
2. With sync: House is left for another tab → `openHomeID` is cleared (by design, to let sync write). A foreground
   sync pulls another device's newer X and writes it. Returning to House does not re-set `openHomeID` or reload; the
   next edit writes the stale model + edit over the pulled one, and the next sync pushes it as a local edit, overwriting
   the other device's work on the server too.

**Expected behavior:** An editor either reloads when the file changed underneath it (compare `meta.modified`/fingerprint
on appear) or is the single owner every other writer goes through; the sync guard is re-armed whenever the editor is
visible with a live session.
**Why this matters:** Silent loss of user edits, and in the sync case, silent loss across devices.
**Evidence:** Code reading of all writers (`grep -rn '\.save(model:' escape_plan`), and of `loadIfNeeded`'s guard. The
tab-lifecycle half (whether `onDisappear` fires on tab switches) follows SwiftUI `TabView` behaviour and should be
confirmed on a simulator before and after the fix.
**Affected systems:** House editor, Home re-scan diff, onboarding interview, cloud sync, score (scores a file the
editor is about to overwrite).
**Likely root cause:** One `HomeModelStore` per screen instance instead of one per home (see 01 §5.1).
**Potential fix direction:** Minimal: on `onAppear`, if a session exists, compare the on-disk fingerprint
(`HomeFingerprint.of`) with the session's last-saved fingerprint and reload (or prompt) when they differ; re-assign
`library.editor` and `syncRepository.openHomeID` on appear. Structural: a per-home store owned by `HomeLibrary`.
**Dependencies / considerations:** Reloading discards the undo stack — acceptable, but say so. `SyncReconciler` uses
fingerprints, so reuse `HomeFingerprint`. Must not re-open the old "pull during edit" bug the `openHomeID` guard fixed.

---

### [AUD-014] Switching homes while a score is loading can show the previous home's score; a superseded request shows a false "can't reach server"

**Severity:** P2
**Location:**
- `escape_plan/Screens/ReadinessStore.swift:82-87` (`select`), `:97-129` (`load` awaits `fetchScore` directly),
  `:139-159` (`rescore` cancels only `refreshTask`; `fetchScore` writes `breakdown` unconditionally after `await`)
- `escape_plan/Networking/BackendFailure.swift:112-150` (a cancelled `URLSession` request is `URLError(.cancelled)`,
  not `CancellationError`, so it falls through to "Couldn't reach the server. Check your connection, or the server
  address in Settings.")

**Category:** frontend / state synchronisation
**What I found:** `fetchScore` captures `activeHome` at start and assigns `self.breakdown = new` at the end without
checking that the active home is still the same. `load(api:)` is called from several un-cancelled `Task`s
(`ContentView.task`, `select`, the onboarding completion, the sync `onChange`).
**Current behavior:** On a cold Render start (51 s measured) the user switches from home A to B; A's response arrives
after B's (or B's fails) → the Home card and Tasks list show A's score and checklist under B's name. Toggling one of
those items then writes A's item ids into B's `checklistState` (`toggleDone` saves under `activeHomeID`). Separately,
rapid toggles cancel the previous `/score` through `refreshTask?.cancel()`; the cancelled request surfaces as a
"Couldn't reach the server" banner until the next response lands.
**Expected behavior:** Drop any response whose home id ≠ current `activeHomeID`; treat `URLError.cancelled` like
`CancellationError`; route every score fetch through one cancellable task.
**Evidence:** Code reading. `ScoreBreakdown` carries no home id, so the client cannot detect the mix-up after the fact.
**Affected systems:** Home, Tasks, Score screens; checklist persistence; ScoreCache (saved under the right id, so the
cache is not corrupted).
**Potential fix direction:** In `fetchScore`, `guard activeHomeID == home.id else { return }` after the await; map
`URLError(.cancelled)` to a no-op in `ReadinessStore` and `BackendFailure`.
**Considerations:** `isScoring` has the same overlap problem (the first finisher clears it while another is in flight).

---

### [AUD-017] The re-scan "Add to Home" path bypasses the reducer and swallows save errors

**Severity:** P2
**Location:** `escape_plan/Screens/HomeScreen.swift:84-91`
**Category:** frontend / data integrity
**What I found:** `home.floors[floorIdx].objects.append(obj)` mutates a `HomeModel` value in the view, then
`try? library.store.save(model: home)` and `readiness.replaceActiveHome(home, …)`.
**Current behavior:** No `EditorValidation` (the documented "only `HomeModelStore` mutates a model" rule is broken
here), no undo entry, and a failed save is invisible while the in-memory score is recomputed as if it succeeded. The
new object is appended to the floor that holds the room but is not checked to lie inside the room. See also AUD-013
(House later overwrites this write).
**Expected behavior:** Dispatch an `EditAction.addObject` through a `HomeModelStore`, surface a save failure, and
refresh the House session.
**Evidence:** Code reading; `escape_plan/CLAUDE.md` "Hard rules".
**Potential fix direction:** Reuse the same store House uses (depends on AUD-013's structural fix) or build a temporary
`HomeModelStore` for the dispatch. **Considerations:** Diff objects are `category: "other"`, `source: "scan"`,
`confidence: 0.3` by server design (`backend/app/routing/diff.py:131-134`).

---

### [AUD-019] Screens create their own `HomeDocumentStore()` and ignore the launch fallback (known)

**Severity:** P3
**Location:** `HouseScreen.swift:207,213`, `DrillMode/DrillScreen.swift:747`, `ProfilesScreen.swift:33`,
`BuildFromPlanView.swift:212`, `SettingsScreen.swift:243`, `Onboarding/OnboardingState.swift:155`
**Category:** frontend / reliability
**What I found / current behavior:** When Documents cannot be opened, the app runs on a temp-directory store and shows
a banner — but these screens open the real Documents path again (and `HouseScreen` does so on every struct init, i.e.
on SwiftUI re-evaluation). In the fallback state their writes go to a different directory than the library reads.
**Expected behavior:** Pass the launch store down (it is already in `HomeLibrary.store`).
**Evidence:** Already listed in BLOCKERS "Found while doing this"; confirmed still true by grep on 2026-09-28.
**Potential fix direction:** Inject `library.store`. Low risk.

---

### [AUD-033] One conversation slot for all homes; history grows without bound

**Severity:** P3
**Location:** `escape_plan/Persistence/ConversationStore.swift` (single `Documents/Assistant/conversation.json`),
`escape_plan/Screens/AssistantScreen.swift:330-395`
**Category:** frontend / UX / cost
**What I found:** `load(forHomeID:)` returns the thread only if its `homeID` matches; `save` overwrites the single
file. Every send posts the full history (`messages.map(\.wireMessage)`).
**Current behavior:** Chat about home A, switch to B, send one message → A's thread is overwritten and lost. Long
threads send ever more tokens per turn until the model's context limit returns a 400 (surfaced as 502 "AI rejected"),
and the thread is stuck until "New chat".
**Expected behavior:** One file per home (like `HomeDocumentStore`), and a server- or client-side cap (last N turns).
**Evidence:** Code reading. **Considerations:** Backend `ChatRequest.messages` has no `max_length` either (AUD-035).

---

## Smaller frontend observations (not separately indexed)

- `ContentView.swift:80`, `HomeLibrary.swift:35-37` and `SyncReconciler.swift` comments say "the backend has no delete
  endpoint"; `DELETE /homes/{id}` exists since S11.7. Misleading for whoever fixes AUD-021 (tracked as AUD-039).
- `HomeScreen`'s "Build Manually" pushes `HouseScreen(homeID: nil)`, which **saves a blank "New Home" immediately**
  (`HouseScreen.swift:2249-2252`) even if the user backs out; with no delete UI these accumulate (part of AUD-021).
- `blankHome()` uses `UUID().uuidString` (upper-case) while every other creator lower-cases ids — harmless, inconsistent.
- `HomeThumbnailView` (`Screens/HomeThumbnailView.swift`) and `FixtureLibrary` (`Renderer/FixtureLibrary.swift`) have no
  references outside their own files (dead code, AUD-044).
- Mock/preview scaffolding (`MockTimeline`, `SyncPreviewSupport`) is correctly `#if DEBUG`-guarded — checked.
