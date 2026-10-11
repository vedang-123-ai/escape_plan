# 19 — Cross-System Findings (lead synthesis)

**How this was produced, and its limits.** The lead did not simply concatenate. It indexed every CRITICAL/HIGH finding across reports 01–18, read Agent 18's independent verdict table, and personally re-checked the findings below against source or by running commands. **The lead did not read every line of all ~8,000 lines of agent reports**; findings that the lead did not re-check carry the originating agent's verification label and are marked *(agent-reported)*. Where the lead's severity differs from an agent's, the reason is given. Reports 00–21 all exist in this directory.

## 1. Lead re-verification results

| Finding | Original | Lead action | Result | Lead severity |
|---|---|---|---|---|
| A14-01 device build fails (`RoomCaptureController.swift:118`) | CRITICAL | Re-ran `xcodebuild build generic/platform=iOS -configuration Release` | **Reproduced** (exit 65, same error). Simulator build/tests succeed because the line is inside `#if !targetEnvironment(simulator)` | **CRITICAL** for any real-device/TestFlight build; trivial fix; may be a newer-SDK behaviour change (the repo's docs claim past device runs on an earlier toolchain — not verified) |
| A14-02 token in app bundle | HIGH | Listed Debug simulator `.app`; `git check-ignore` | **Confirmed**: `BackendConfig.local.json` is gitignored but copied into the bundle (also `CLAUDE.md`, `README.md`) | HIGH |
| A17-01 PDF omits score/safe room | CRITICAL | Read `EscapePlanExporter.writePDF`/`writeResponderSnapshot`, `EscapePlanPDF.swift:255-285` | Code does omit it in `writePDF`; the score/safe-room/hazard block is in a per-floor section that Agent 18 says is responder-only (the lead saw the code but did not trace which document type reaches line 266) | **False positive / at most LOW (design question)** |
| A07-01 `deletionObserver` disconnected | CRITICAL | Read `ContentView.swift:75-95` | Disconnection is **deliberate and commented** ("demo trim, 2026-10-02": accounts and sync off). Real risk only if sync is re-enabled | LOW/OBSERVATION |
| A15-02 `UIFileSharingEnabled` | HIGH | Read `project.pbxproj` | Set only in the **Debug** configuration block (Release block lacks it) | LOW |
| A15-03 delete-account treats 401 as success | HIGH | Read `AuthSession.deleteAccount()` | Behaviour real, **intentional and commented** ("already gone"). Genuine residual issue: a 401 from an *expired* token is indistinguishable, so the UI can claim erasure while server data remains. Accounts are off in the demo build | MEDIUM |
| A04-03 no CO coverage | HIGH | grep scoring/models/corpus | CO appears only in the tornado doc (generator safety); **no CO alarm checklist/score rule** (Agent 4 also cites an enum in models) | MEDIUM — a content gap against USFA/NFPA guidance, not a defect in a claimed feature (docs scope is fire/quake/tornado readiness; check whether any screen claims CO coverage — none found) |
| A07-03 duplicate keeps entity IDs | HIGH | Read `HomeDocumentStore.duplicate` / `HomeDocument.reidentified` | **Confirmed in source**: only `home_id`, name, meta change; room/door IDs copied verbatim. Consequence (collision) depends on any store keyed by child ID across homes; not demonstrated | MEDIUM |
| A08-01 PDF vs 3D vertical mirror | HIGH | Read `PlanProjection.swift` header/`point()` and Agent 8's `DollhouseGeometry` excerpt | `PlanProjection` maps plan +y → page-down with no flip; `DollhouseGeometry` maps plan +y → scene −z (up on screen from default camera). The two disagree **by source reading**. Not visually compared at runtime | HIGH (confidence Medium; needs a side-by-side render) |
| Test baselines | — | Ran suites | iOS 1150 pass/0 fail/3 skip; backend 1258/1 skip; see report 21 | — |

## 2. Findings independently found by multiple agents
- **Stale `ScoreCache` shown or exported as current** — A07-02 (persistence), A10-01 (reliability): same root cause (cache keyed by home ID only, no model fingerprint or age, `escape_plan/Export/EscapePlanExporter.swift:115`). Merged into **X-01** below.
- **502/503 from the edge proxy bypasses the offline route cache** — A10-02 and A18-03: merged as **X-02**.
- **Misleading score attribution under the 40-point structural cap** — A17-03 and A18-04.
- **Monthly alarm test never recurs** — A04-01 (content), A09-03 (notifications), both pointing at `alarm.test_monthly` / `FORMERLY_RECURRING_IDS` (recurrence removed in the demo trim; the task text and USFA monthly-test guidance disagree). Merged **X-03**.
- **Dead/zombie auth and sync code** — A01-06, A02-05, A07-01, A15-03, A17-05 all trace back to one decision (accounts and sync switched off, 2026-10-02) leaving compiled code and comments but no integration. Merged **X-04**.
- **`HouseScreen` monolith** — A01-01/02/03, A02-01/02/04, A11-01 and A11-02.
- **Geometry frames disagree** — A08-01 and A08-02 and A18-02 (PDF vs 3D vs RoomPlan converter).

## 3. Contradictions and how they resolved
| Contradiction | Resolution |
|---|---|
| Agent 10: stale `ScoreCache` is exported to responders; Agent 17: PDF *never* loads `ScoreCache` | Both are about **different export paths**. Responder snapshot loads the cache (`EscapePlanExporter.swift:115`); the family `writePDF` does not. Agent 17's "omission" is intended; Agent 10's staleness concern stands (X-01). |
| "Simulator runtime blocked" (Agents 3, 5, 7, 8, 9, 11, 12, 14) vs "iOS 27.0 runtime installed" (Agents 16, 18) | Both true at different times: lead saw no runtimes at 00:18, an iOS 27.0 runtime at 00:43. **All "blocked" runtime statements are stale**; nothing in reports 02, 03, 05, 08, 10, 11, 12 was runtime-checked even though it now could be. |
| Agent 3 said runtime check was prohibited by "rule 5" | Misreading: rule 5 only limited who may run `xcodebuild`; `simctl` was never prohibited. Visual claims rely on pre-existing repository screenshots plus source. |
| A12-01 CRITICAL vs A18 MEDIUM (editor is gesture-only) | Lead sides with MEDIUM: an accessibility limitation of a spatial editor is real but doesn't break a core safety workflow; a VoiceOver-accessible alternative (list-based room editing) would be the proper fix. |
| A05-01 test names (Agent 5: `GoldenPathRecordingUITests`/`S44ScreenshotUITests`; Agent 18: `OnboardingFlowUITests`) | Not reconciled — no one ran the UI tests. Treated as *unverified*. |
| Test counts in `BLOCKERS.md` (1008/932/635) vs measured (1150/1258/656) | Different date/scope; not a contradiction in code. |

## 4. False positives / over-severity adjustments
A17-01 (false positive); A07-01 (documented trim); A15-02 (Debug only); A15-03 (intentional, residual MEDIUM); A12-01 (over-severe); A15-04 COPPA (see below); A17-04 and A17-05 (consequences of decisions: "app draws fire routes only" (2026-10-05) and accounts off); A04-02 (NFPA 72 supports alarms in/outside sleeping areas, Agent 18 → LOW); A01-01..03 (maintainability, not user-facing; MEDIUM given the Oct 24 deadline).
**A15-04 (children's PII / COPPA):** COPPA regulates operators collecting personal information *from children under 13*; here a parent/adult enters household member details. The privacy-disclosure concern is real (names, ages/mobility needs, bedrooms sent to a server and, per the docs, to an LLM provider via the backend) but the COPPA framing is the agent's legal inference — *needs a qualified review*. Lead severity MEDIUM. *(not re-verified in code)*.

## 5. Common root causes
1. **Late product trims left behind scaffolding** (accounts/sync, practice reminders, multi-peril drawing): code, copy, docs, tests and corpus text disagree about what exists (X-03, X-04, A09-02, A16 claims drift).
2. **No single source of truth for derived data**: scores, routes and caches are keyed by home ID but not by model state or age (X-01, A07-02, offline route labelling).
3. **Three coordinate frames, three hand-written transforms** (RoomPlan → plan → SceneKit/PDF) with no round-trip test (A08-01/02).
4. **Client/backend validation parity not enforced** (A17-02 overlap rule; Swift `EditorValidation` vs pydantic).
5. **Gate covers logic, not seams or device slice** (report 13; A14-01 hid behind the simulator-only gate).
6. **UI state concentrated in one 2,875-line view** driving most architecture and performance observations.
7. **Secrets and internal docs ride along via the synchronized root group** (A14-02/04).

## 6. Cross-system issues (X-series)
**X-01 [HIGH] Cached readiness score/hazards presented without age or model-match.**
Location: `ScoreCache` + `EscapePlanExporter.writeResponderSnapshot:115` + offline score display. Observed: score stored per home ID; after editing the home, an offline launch can show an old score; the responder snapshot embeds whatever is cached. Impact: a family may hand a fire department a hazard summary describing a different version of the house. Disclaimer text mitigates but does not state age. Verification: source (lead read the export path; cache fingerprint absence per Agents 7/10, *agent-reported*). Confidence Medium-High. Effort Small–Medium.

**X-02 [HIGH] Gateway/proxy failures do not trigger the offline fallback.** `APIClient+Cache.swift` `isConnectionFailure` only recognises transport errors (Agents 10 and 18, *agent-reported*; lead did not open the file). Combined with the documented exhausted-credits 502 on AI endpoints and Render cold starts, the likely demo failure (backend 502) may show an error instead of last-known routes. Effort Small.

**X-03 [MEDIUM] "Monthly smoke-alarm test" is a one-time task.** Recurrence was deliberately removed; the card still implies a recurring check. USFA recommends testing alarms monthly (Agent 4 cites the source in report 04 — the lead did not re-fetch). Effort Small (reword or restore recurrence).

**X-04 [MEDIUM] Auth/sync zombie subsystem.** Compiled, tested, partly unreachable; documentation and BLOCKERS still describe it. Risk is mostly confusion for judges and engineers, plus latent bugs if turned back on (A07-01, A15-03, A17-05).

**X-05 [HIGH] Geometry inconsistencies** (A08-01/02) — see §1.

**X-06 [HIGH] Distribution blockers cluster:** A14-01 (device build), A14-02 (token in bundle), A14-03 (Release without local config has no token and the Settings entry is `#if DEBUG`), A15-01 (privacy manifest), A14-05 (encryption key). One "release hygiene" sprint clears all.

## 7. Features implemented but not integrated
Multi-peril routing (backend only), `/analyze` `/explain` `/diff_obstructions` endpoints without active client callers (A06-03), `FixtureSeeder.seedDemoHome` (A05-02), `Renderer/Fixtures` and `MockTimeline` compiled into the app target (Agents 1/17), CA strapping tip (A08-03).

## 8. Testing insufficiency
See report 13. The suite passes in the presence of every HIGH finding except A14-01's compile failure, which passes only because the gate never compiles the device slice.

## 9. Gaps in audit coverage (honest list)
- **No runtime UI exploration**: the simulator runtime appeared late; only a launch smoke was done. Screen-level claims (nested NavigationStack back-button trap, tab-bar occlusion, Dynamic Type clipping, contrast) are source/screenshot-based. This is the single biggest recommended follow-up now that a runtime exists.
- **UI tests not run**; **no Instruments**; **no physical-device or LiDAR test**; **no live backend/AI test**.
- Fire-safety content was verified by Agent 4 against online sources; the lead did not re-fetch any source. A qualified fire-safety professional has not reviewed anything.
- Agent 16's reading of the Congressional App Challenge rules (A16-01/02) was not re-checked by the lead against the official site; **re-read the official rules before relying on it**.
- Testing report 13 was written by the lead after three failed agent attempts and is thinner than the others.

