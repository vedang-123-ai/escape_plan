# 14 · Feature Completeness

Canonical home for AUD-020, AUD-021, AUD-022, AUD-023. Matrix of every major feature against what a user can
actually reach in the shipped build (branch `drill-3d-fallback`, 2026-09-28).

## Feature matrix

| Feature (spec / pitch) | Backend | iOS client code | Reachable in UI | Works end-to-end | Notes |
|---|---|---|---|---|---|
| LiDAR scan → HomeModel | `/convert` ✅ | `ScanFlowView`, `APIClient+Convert` ✅ | Home "+" → Scan New Home ✅ | Device-only, unverified (BLOCKERS §2) | Raw scans never cleaned (AUD-008) |
| Manual editor | n/a | `HouseScreen` ✅ | House tab, Home "+" → Build Manually ✅ | ✅ (type-checked, UI tests pass) | Stale-copy overwrite (AUD-013); abandoned blank homes persist (AUD-021) |
| Text/photo/PDF builder (draft only) | `/build` ✅ | `BuildFromPlanView` ✅ | Home "+" → Import Plan ✅ | ❌ AI credits out (AUD-002); photo path mislabelled (AUD-024); **draft scored without review** (AUD-023) | |
| Routes per peril, per person | `/routes` ✅ | ✅ | House ✅ | ✅ when token valid (AUD-001) | Per-person needs profiles (AUD-020) |
| Readiness score + checklist | `/score` ✅ | `ReadinessStore` ✅ | Home, Tasks, Score ✅ | ✅ | Recurrence dead (AUD-026); race on switch (AUD-014) |
| Household profiles CRUD | n/a (in HomeModel) | `ProfilesScreen`, `ProfileEditorView` ✅ | ❌ **no entry point** | ❌ | AUD-020 |
| Practice drill (3D) | `/routes`, `/evacuate` | `DrillScreen` ✅ | Home drill card, Tasks "Run a drill" ✅ | ⚠️ only for homes that already have profiles; fix is unpushed (AUD-034) | AUD-020, AUD-025 |
| AR drill | n/a | `Drill/ARDrillView` | Opt-in button on LiDAR phones | Never run on a device (BLOCKERS) | |
| Fire simulation | `/evacuate` ✅ | House ignite ✅ | ✅ | ✅ | |
| Hazard hunt (guided tagging) | via `/score` | `HazardHuntView` ✅ | House ✅ | ✅ | |
| Partial re-scan (re-check a room) | `/diff_obstructions` ✅ | Home ✅ | Task detail "Re-check a room" ✅ | ⚠️ device-only; add bypasses reducer (AUD-017); retry broken (AUD-029) | |
| AI inspector ("audits") | `/analyze` ✅ (tested) | `APIClient+Analyze` ✅ | ❌ **no call site** | ❌ | AUD-022 |
| AI route explanation | `/explain` ✅ | ❌ no client method | ❌ | ❌ | AUD-022 |
| Assistant chat | `/chat` ✅ | `AssistantScreen` ✅ | ✅ | ❌ credits out (AUD-002); first message after idle times out (AUD-032) | AUD-030, AUD-033 |
| Export PDF plan | n/a | `ExportPlanSheet` ✅ | Tasks ✅ | ✅ | |
| Share with fire department | n/a | Tasks card ✅, Settings ✅ | ✅ | ⚠️ Settings path uses the wrong home, fails silently (AUD-027) | |
| Delete / duplicate / rename home | n/a (local) + `DELETE /homes/{id}` | `HomeLibrary.delete/duplicate` ✅ | ❌ delete/duplicate; rename only inside House "More" | ❌ | AUD-021 |
| Export home JSON / import JSON | n/a | `HomeDocumentStore.export/importDocument` ✅ | ❌ | ❌ | AUD-021 |
| Accounts (optional) | `/auth/*` ✅ | ✅ | Gate + Settings ✅ | ✅ (met production 2026-09-16) | 60-min session (AUD-031) |
| Cloud sync (optional) | `/homes` ✅ | `SyncManager` ✅ | automatic ✅ | ⚠️ | AUD-015, AUD-016, AUD-018, AUD-031 |
| Delete account | `DELETE /auth/me` ✅ | ✅ | Settings ✅ | ✅ | |
| Practice reminders | n/a | `PracticeReminderScheduler` ✅ | Drill ✅ | not verified here | |
| Loading tips | n/a | `LoadingTipView` ✅ | Score/Drill/Export/scan waits ✅ | ✅ | |

---

### [AUD-020] Household profiles cannot be added or edited after onboarding — the Profiles screen lost its only entry point

**Severity:** P1
**Location:**
- `escape_plan/Screens/ProfilesScreen.swift` (full CRUD; only reference outside the file: none — its own `#Preview`)
- Removed entry point: `escape_plan/Screens/BetaScreen.swift` (deleted in `87c0610`, 2026-09-25, audit item B9) had
  `.navigationDestination(item: $profilesHomeID) { ProfilesScreen(homeID:) }` and two "Profiles" buttons
- `escape_plan/DrillMode/DrillScreen.swift:146-151` — empty state: "Add family members in Profiles first — the drill
  walks one person's escape route."
- `escape_plan/Onboarding/OnboardingState.swift:76-130` — the only other profile writer, runs once, writes to the
  then-active home

**Category:** feature completeness / UX (dead end)
**What I found:** Profiles drive per-person routes (`/routes profile_id`), the drill (which walks one person's route),
the evacuation animation, the snapshot's vulnerable-occupant list, and several checklist items. After the revamp,
nothing in the UI opens `ProfilesScreen`.
**Current behavior:** A user who scans or builds their own home gets a home with **no profiles** (scans and blank homes
never have any; only the seeded `apartment`, `twostory`, `jagged` fixtures do). Starting a drill on it shows "Add
family members in Profiles first" — and there is no Profiles screen to go to. House's person picker is empty. The
onboarding interview wrote profiles only to whatever home was active during onboarding (usually a demo fixture).
**Expected behavior:** Profiles reachable for the active home (Home top bar, Tasks "Family plan" section, or House),
and the drill's empty state links straight to it.
**Why this matters:** The practice drill is the product's core readiness action; for the user's real home it is a
dead end. The demo works only because demo fixtures carry seeded people.
**Evidence:** `grep -rn "ProfilesScreen(" escape_plan` → only `ProfilesScreen.swift:239` (#Preview);
`git show 87c0610^:escape_plan/Screens/BetaScreen.swift` lines 106, 219, 236 show the old entry points.
**Affected systems:** Drill, per-person routing, evacuation playback, responder snapshot, household checklist items.
**Likely root cause:** BetaScreen deletion without re-homing its navigation destinations (01 §5.2).
**Potential fix direction:** Add a `navigationDestination` for `ProfilesScreen(homeID: readiness.activeHomeID)` from
Home (and from the drill's empty state); pass `library.store` (AUD-019) and call `readiness.load` on dismiss.
**Dependencies / considerations:** `ProfilesScreen` writes the home file directly, so it is another writer for AUD-013 —
refresh the House session afterwards. Add a UI test that reaches Profiles from Home.

---

### [AUD-021] Homes cannot be deleted, duplicated, exported as JSON or imported; abandoned and demo homes accumulate

**Severity:** P1
**Location:**
- `escape_plan/Persistence/HomeLibrary.swift:54-72` (`delete`, `duplicate`, `export` — no callers in `Screens/`)
- `escape_plan/Persistence/HomeDocumentStore.swift:200-218` (`importDocument` — no caller anywhere)
- `escape_plan/Screens/HomeScreen.swift:142-196` (home switcher menu: switch only; "+" menu: scan / build / import plan)
- `escape_plan/Screens/HouseScreen.swift:2249-2252` (a new blank home is saved as soon as the editor opens)
- `escape_plan/escape_planApp.swift:58-72` (three starter homes seeded into every library, fixed `home_id`s)
- Server side wired but unreachable: `DELETE /homes/{id}` (`api_auth.py:187-201`) is only called from the sync
  tombstone path, which only a local delete creates

**Category:** feature completeness / data hygiene
**What I found:** The revamp's Home tab exposes switching only. `BetaScreen` used to offer Delete, Duplicate, Export,
Score, Profiles, Drill per home.
**Current behavior:** A user cannot remove the three demo homes, a failed scan's result, an AI draft they rejected, or
the blank "New Home" created every time they tap "Build Manually" and back out. Each is also uploaded to their cloud
account if they sign in (the starter homes' fixed ids mean every device uploads the same three). S11.7's server-side
delete (and its reviewed ownership rules) can never run.
**Expected behavior:** Delete (with confirmation) and Duplicate from the home switcher; blank homes saved only after the
first real edit; demo homes clearly labelled and removable.
**Why this matters:** Clutter compounds every other problem (wrong home shared — AUD-027; conflict copies —
AUD-015), and "delete my home" is a basic privacy expectation, especially for a home that carries an address and
household members.
**Evidence:** `grep -rn "delete(homeID\|duplicate(homeID" escape_plan --include='*.swift'` → only `Persistence/` and `Sync/`;
`grep -rn importDocument escape_plan` → definition only.
**Affected systems:** Library, sync tombstones, cloud storage, snapshot/export pickers.
**Potential fix direction:** Context menu or swipe actions on the switcher's rows calling `library.delete` (which
already notifies the editor and the sync tombstone observer); defer `autosave` of a blank home until first commit.
**Dependencies / considerations:** Deleting the active home must call `readiness.ensureActiveHome()` and
`router.clearHouseRequest()`. The tombstone/ownership rules in `SyncManager` (2026-09-24 decisions) must hold — add
tests for "delete a starter home before signing in".

---

### [AUD-022] The AI inspector (`/analyze`) and route explanation (`/explain`) are not reachable from the app

**Severity:** P1
**Location:**
- `escape_plan/Networking/APIClient+Analyze.swift` (client exists; `grep` finds no caller)
- No iOS client for `/explain` at all
- Unwired in `dac8673` (2026-09-06, "Update schema version to 2.0 and implement multi-peril routing"), which removed
  `api.analyze(home:)` from the old screen
- Claims that depend on it: `docs/demo/script-v1.md:105-115` (Beat 5: "Our AI inspector walks the model…", "The AI
  explains and it inspects"), `CLAUDE.md` ("A server-side Claude layer explains, chats and audits"), README
- Downstream: `ScoreRequest.findings` is never sent from iOS, so the `agent_finding` checklist category
  (`ReadinessStore.swift:211`) can never appear

**Category:** feature completeness / pitch truth
**What I found:** Two of the three advertised AI roles ("explains", "audits") have backend code, tests and evals, but
no user path. Only chat and the builder are wired.
**Current behavior:** Nothing in the app calls `/analyze` or `/explain`. The demo's Beat 5 cannot be filmed from the
current build.
**Expected behavior:** Either wire the inspector (e.g. a "Run an inspection" action on Home/House, results fed into
`/score` as `findings`) or change the pitch to what ships.
**Why this matters:** `pitch-truth-auditor` exists precisely for this; judges test claims. Also the AI credits are out
(AUD-002), so even once wired it needs a funded key to demo.
**Evidence:** `grep -rn "\.analyze(\|\.explain(" escape_plan` → 0 call sites; `git log -S ".analyze(home" -- escape_plan`.
**Affected systems:** Pitch, demo script, checklist (`agent_finding`), score (`findings` component always full marks).
**Potential fix direction:** Product decision first (owner): re-wire or re-word. If re-wiring, the old call site in
`dac8673^` is a starting point; route failures through `BackendFailure(.analysis)`.
**Dependencies / considerations:** Cost guard applies (AUD-003/035). Findings must stay evidence-linked (server
validates).

---

### [AUD-023] AI-drafted homes are scored immediately; the "mandatory editor review" only exists inside House

**Severity:** P1
**Location:**
- `escape_plan/Screens/HomeScreen.swift:95-100` (`BuildFromPlanView { homeID in library.refresh(); switchHome(to: homeID) }`)
- `escape_plan/Screens/HomeScreen.swift:203-208` → `ReadinessStore.select` → `/score` (computes three route plans)
- `escape_plan/Screens/HouseScreen.swift:1623-1633` (`needsDraftReview` = `hasAIDraftContent` blocks routes in House only)
- Claims: `docs/playbook/01-product-spec.md:39` ("Draft-only, mandatory editor review, never presented as scan
  parity"), `backend/app/main.py:449-450`, `escape_plan/CLAUDE.md:48`, `APIClient+Build.swift:4`
- Previous behaviour: `git show 87c0610^:escape_plan/Screens/BetaScreen.swift` lines 79-99 opened `HouseScreen` right
  after a build

**Category:** cross-system / safety integrity / regression
**What I found:** After `/build`, the draft becomes the active home and Home immediately requests `/score`, which
computes fire/tornado/earthquake routes and a readiness score on an unreviewed AI draft. House correctly refuses to
draw routes for the same model until the draft is reviewed.
**Current behavior:** The user sees a readiness score and band for a floor plan an LLM guessed from a sentence or a
photo, next to tasks derived from routes that House will not even display for the same model.
**Expected behavior:** After a build, open the editor on the draft (as before the revamp); `ReadinessStore` does not
score a home with `hasAIDraftContent` and shows "Review your draft" instead.
**Why this matters:** It contradicts the spec's scope lock and the defence to "isn't this an AI wrapper?" — the score
is presented as the engine's judgement of the user's home.
**Evidence:** Code reading of the four locations; regression pinpointed by comparing with `87c0610^`.
**Affected systems:** Home, Tasks, Score, Drill (would route an AI draft if it had profiles), responder snapshot
(readiness score in the package).
**Potential fix direction:** `ReadinessStore.fetchScore`: `guard !activeHome.hasAIDraftContent`; Home: route the build
completion to `router.openHouse(homeID:)`.
**Dependencies / considerations:** `hasAIDraftContent` is in `Editor/Core/ModelSupport.swift` (pure, testable in
EditorCore) — add a test there.

## Submission-level completeness (not code features)

- `docs/tools-used.md` vs. AI tools evidenced in the environment — AUD-038 (10_DEPLOYMENT).
- Demo script claims vs build — AUD-022 above; recommend running `pitch-truth-auditor` after fixes.
