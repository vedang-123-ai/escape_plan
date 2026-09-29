# 12 · Technical Debt

Canonical home for AUD-039, AUD-040, AUD-044, AUD-045, AUD-048. Duplicated-helper debt in the backend is AUD-043
(03_BACKEND).

---

### [AUD-039] Comments across iOS still say "the backend has no delete endpoint"

**Severity:** P3
**Location:** `escape_plan/ContentView.swift:80-81`, `escape_plan/Persistence/HomeLibrary.swift:35-37`,
`escape_plan/Sync/SyncReconciler.swift` (the `(local, none)` and `(none, remote)` branches: "the backend has no delete
endpoint")
**Category:** tech debt / documentation
**What I found:** `DELETE /homes/{home_id}` exists since S11.7 (`backend/app/api_auth.py:187-201`) and `SyncManager`
calls it. The comments describe the pre-S11.7 world, including the rationale for re-creating a home whose server copy
vanished — which is now also the path by which a home deleted on another device is resurrected (documented as a known
one-way limitation in `docs/decisions.md` 2026-09-24).
**Why this matters:** Whoever fixes AUD-021 will read these comments first and reason from a false premise.
**Potential fix direction:** Update the three comments; link the 2026-09-24 decision row.

---

### [AUD-040] Stray scratch scripts and a prompt file at the repo root

**Severity:** P3
**Location:** `scratch_fix_persistence.py`, `scratch_fix_persistence2.py`, `scratch_fix_persistence_tests.py`,
`scratch_migrator.py`, `improved_prompt.md` (all tracked)
**Category:** tech debt / hygiene
**What I found:** One-off rewrite scripts from the 1.1 → 2.0 migration. Running them today would rewrite
`SchemaMigrator.swift` and `PersistenceTests.swift` back to 2.0-era values (`currentVersion = "2.0"`, expected versions
"3.0"/"2.0"), silently breaking the 2.1 contract.
**Why this matters:** Judges and new contributors read the root; these look like tooling. `escape_plan/CLAUDE.md` says
the synchronized project group means "no stray scratch files" — true for Swift, not for the root.
**Potential fix direction:** Delete them (history keeps them); move `improved_prompt.md` under `docs/` if it is still used.

---

### [AUD-044] Dead code in the app target

**Severity:** P3
**Location:** `escape_plan/Screens/HomeThumbnailView.swift` (no references outside its file),
`escape_plan/Renderer/FixtureLibrary.swift` (`FixtureLibrary` referenced only by its own definition),
`escape_plan/Screens/ProfilesScreen.swift` + `ProfileEditorView.swift` (unreachable, AUD-020 — **re-wire, don't delete**),
`escape_plan/Networking/APIClient+Analyze.swift` + `Models/AnalyzeModels.swift` (no caller, AUD-022)
**Category:** tech debt
**Evidence:** A sweep of every top-level type for references outside its own file (`grep -rlw`), then manual checks.
**Potential fix direction:** Delete the first two after confirming no preview/test depends on them; the rest are
feature decisions.

---

### [AUD-045] `HouseScreen.swift` is 2,726 lines (known, deferred)

**Severity:** P3
**Location:** `escape_plan/Screens/HouseScreen.swift`
**Category:** tech debt / maintainability
**What I found:** Editor, route viewer, fire simulation playback, hazard emphasis, tours, rename/delete floor, sheets
and accessibility text in one view. AUD-013's fix will have to touch its load/save lifecycle.
**Evidence:** Already on BLOCKERS "Deferred on purpose (do not do in a fix session): HouseScreen decomposition — split
during the upcoming House redesign". Recorded here only so the implementation order accounts for it.
**Potential fix direction:** Extract `HouseEditorSessionController` (load/autosave/registration) first — that is also
the seam AUD-013 needs.

---

### [AUD-048] Tracker and playbook statements that are now wrong

**Severity:** P3
**Location:** `docs/tracker/BLOCKERS.md`, `docs/playbook/README.md`, `docs/tracker/notes/`
**Category:** documentation drift (this repo's rule: anything unverified goes in BLOCKERS; remove a line only when verified)
**What I found:**
1. BLOCKERS §3: `EvacuationMockTimelineTests` "passes in EditorCore … find what differs between the two runners" — it
   never runs in EditorCore (`#if !SWIFT_PACKAGE`); the failure is a stale expectation (AUD-036).
2. BLOCKERS "Audit remediation Part A": "Deployed backend NOT smoke-checked" — verified today: `/health` 200,
   `/diff_obstructions` without token 401.
3. BLOCKERS §3 lists the two gate UI failures as "S11.7 shipped these without a simulator" — the root cause is test
   isolation (AUD-036), and a third `SignedOutPathUITests` test (`testTheGateCanBeDismissedWithoutAnAccount`) also fails
   locally for the same reason.
4. BLOCKERS header stamp and §0: iOS counts are from CI on 2026-09-25; today's local run is 987 / 972 / 7 / 8, and
   `GestureFrameCostUITests` passed (it failed in the revamp CI run).
5. `docs/playbook/README.md`: S11.1–S11.4 are not marked DONE although each has a session note (2026-09-21/22) and a
   BLOCKERS section; S11.5–S11.7 files still exist though the rule says shipped files are deleted (the file records the
   rule as contested — pick one).
6. No session note exists for the Linear revamp merge (`ui-revamp-1-foundation`) or for the drill fix (`drill-3d-fallback`)
   — "No note, no DONE".
7. BLOCKERS does not record that the revamp removed the Profiles, delete and duplicate entry points (AUD-020, AUD-021).
**Potential fix direction:** A `/tracker` pass that applies each correction with today's evidence (this directory).
