# 20 — Remediation Roadmap

Severities are the **lead-adjudicated** ones from `19_CROSS_SYSTEM_FINDINGS.md`, not necessarily the originating agent's. Deadline per repo docs: submit by **2026-10-24**. "Effort" assumes one engineer familiar with the code. Items marked *(agent-reported)* were not re-verified by the lead. Nothing here has been implemented.

## Master table
| Priority | Finding | Domain | Evidence / Location | Root Cause | User Impact | Proposed Fix | Effort | Dependencies |
|---|---|---|---|---|---|---|---|---|
| P0 | A14-01 Device/Release build fails | Build | `RoomCaptureController.swift:117-118` `let configuration` mutated; lead reproduced exit 65 | Config is a value type on the current SDK; gate compiles simulator only | No on-device build, archive or TestFlight; LiDAR scan unusable on a real phone | Make it `var` (also review the other `startScan` path); add device-slice build to the gate | Small | A13-01 |
| P0 | A14-02 Backend bearer token bundled in app | Build/Privacy | Token file gitignored yet present in `.app`; internal `CLAUDE.md`/`README.md` too | Xcode synchronized root group copies everything | Anyone with the IPA/app can extract the shared token | Move config out of the synchronized group; inject at build time; exclude docs; rotate the token if any build was shared | Small–Medium | A14-03 |
| P0 | A16-03 / BLOCKERS: AI endpoints 502 (credits exhausted) | Competition/Reliability | `docs/tracker/BLOCKERS.md`; Agent 16 *(live behaviour not re-verified)* | External billing; demo depends on it | Assistant/Explain fail in a live demo | Fund the account or plan an offline-safe demo cut; pre-warm Render | Small (ops) | X-02 |
| P1 | X-02 Proxy 502/503 bypass offline cache | Reliability | `APIClient+Cache.swift` `isConnectionFailure` *(agent-reported)* | Only transport errors treated as offline | Backend hiccup shows an error instead of last-known routes | Treat 502/503/504 like offline; label cached routes with age | Small | X-01 |
| P1 | X-01 Stale `ScoreCache` (A07-02, A10-01) | Persistence/Reliability | `EscapePlanExporter.swift:115` | Cache keyed by home ID, not model state/age | Old score/hazards presented as current and handed to a fire department | Store model fingerprint + timestamp; show age; refuse/flag stale in snapshot | Small–Medium | A07-04 |
| P1 | A08-01/A08-02 Frame inversion | Geometry | `PlanProjection.swift` vs `DollhouseGeometry.swift`; `backend/app/convert/roomplan.py` | Hand-written transforms, no round-trip test | Printed plan may be a mirror image of the 3D home; scanned homes may be mirrored | First render both side by side (runtime check); then fix one transform and add an asymmetric-room round-trip test | Medium | A17-02 |
| P1 | A02-01/A02-02 Nested stack / no back affordance | Frontend | `HomeScreen`→`HouseScreen` navigation *(source only, never run)* | Two NavigationStacks, hidden back | Possible trap on "Build manually" entry | Run on the simulator to confirm; if real, remove inner stack/add dismiss | Small–Medium | A01-07 |
| P1 | A17-02 Overlap validation mismatch | Consistency | `EditorValidation.swift` vs backend/schema *(agent-reported)* | Rules duplicated, not shared | Imported/AI-built homes may be uneditable | Align rules or auto-repair; add parity test | Medium | — |
| P1 | A17-03 / A18-04 Score attribution under cap | Content/UX | `backend/app/scoring/score.py` | Cap not reflected in component list | Explanation blames a 5-pt task for a 40-pt cap | Attribute cap to the structural finding | Small | — |
| P1 | A16-01/A16-02 Submission paperwork | Competition | Agent 16 web research *(re-read official rules)* | Script/docs omit required disclosures; AI-assisted history | Risk of disqualification/credibility | Re-read official rules; add team names, audience, tools, contribution/AI statement | Small | — |
| P1 | A12-02 Banner hides recovery buttons from VoiceOver | Accessibility | `BackendFailureBanner.swift:91` | `.combine` drops child traits | Blind users cannot retry | Use `.contain`/custom actions | Small | — |
| P2 | A03-02 Tab bar occludes bottom content | Visual | pre-existing screenshots (s11-53/56) | Fixed 24–32 pt padding vs floating capsule | Buttons/links partly hidden | Use safe-area inset for the tab bar | Small | — |
| P2 | A14-03 Release without config has no token | Build | `#if DEBUG` Settings entry | Config injection undefined | Authenticated features dead in clean Release | Define Release config path | Small | A14-02 |
| P2 | A15-01 Privacy manifest | Privacy | no `PrivacyInfo.xcprivacy` | Not added | App Store review issue | Add manifest (UserDefaults, file timestamps) | Small | — |
| P2 | A15-03 Delete-on-401 | Privacy | `AuthSession.swift:259-286` | 401 ambiguous | Possibly false "erased" | Distinguish; message honestly | Small | X-04 |
| P2 | A15-04 Household/child data disclosure | Privacy | compute payloads *(agent-reported)* | No explicit notice | Sensitive data sent without clear consent | In-app notice + policy; legal review for COPPA | Medium | — |
| P2 | X-03/A04-01 Monthly alarm test one-time | Content | `checklist.py` `FORMERLY_RECURRING_IDS` | Recurrence cut | Task implies recurring check | Reword to "test now, then monthly" or restore recurrence | Small | — |
| P2 | A04-03 No CO alarm guidance | Content | scoring/checklist lack CO | Scope | Missing common USFA/NFPA prevention item | Add a sourced CO checklist item (expert review) | Small–Medium | corpus |
| P2 | A04-04 PDF omits in-fire rules | Content | `EscapePlanPDF.swift` | Space/scope | Printed plan lacks "stay low, feel doors, close doors" | Add a short sourced block; fire-professional review | Small | — |
| P2 | A10-03 Camera denial → generic error | Reliability | `RoomCaptureController.swift:94` *(agent-reported)* | No permission state handling | Dead end on a denied permission | Detect denied; link to Settings | Small | — |
| P2 | A07-03 Duplicate keeps child IDs | Persistence | `HomeDocument.reidentified` | Only home_id changed | Possible ID collisions | Regenerate or prove scoped | Small | — |
| P2 | A13-02 UI tests bit-rotted | QA | Agent 5 | Env-gated drivers | No first-launch UI coverage | Run, then repair | Medium | — |
| P3 | A12-03/04/05/06/07 contrast, targets, fixed fonts | Accessibility | `HouseScreen.swift:978`, `GlassControls.swift:94`, `AppAppearance.swift:20` | Token choices | Harder under stress/low vision | Fix specifics after runtime check | Medium | — |
| P3 | A11-01/02/03 Performance | Performance | `HouseScreen`, `EvacuationPlaybackCoordinator`, `ExportPlanSheet` | Inferred from code, not profiled | Possible jank/blocked UI | Profile first (Instruments), then fix | Medium | — |
| P3 | A03-01/04/05 dark-mode bleed, ScanFlow drift, iPad | Visual | Info.plist, `ScanFlowView` | — | Polish | After runtime review | Small–Medium | — |
| P3 | A09-02 Docs claim reminders that were removed | Content | `escape-planning-nfpa.md:64`, `smoke-alarms-usfa.md:40` | Trim drift | Corpus promises absent features | Edit corpus | Small | — |
| P4 | A01-01..08 / X-04 Architecture | Architecture | `HouseScreen` 2,875 lines, zombie auth/sync | Trims + organic growth | Maintainability | Extract controllers; delete or isolate dead code **after** submission | Large | — |

## Phase A — Correctness and essential reliability (do first)
1. **A14-01** compile fix + device-slice gate (hours). 2. **X-01** score freshness, **X-02** 502 fallback. 3. **A08-01/02**: *first* run both views on the simulator and compare; fix only what is confirmed. 4. **A17-03** attribution text. 5. **A14-02** token exposure (rotate if any build was shared).
Must-fix before demo/submission: A14-01, A14-02, A08 check, X-02.

## Phase B — Core experience and incomplete functionality
A02-01/02 (confirm on simulator), A17-02, A10-03, A14-03, A07-03, X-03, A04-03/04 (fire-professional review before changing safety wording), A15-03. Re-run the UI tests and repair first-launch coverage (A13-02).

## Phase C — Competition-level polish
A16 paperwork and demo plan (re-read official rules; script must name students, audience, tools; honest AI-assistance statement; pre-warm backend; have an offline-safe demo cut), A12 accessibility items, A03 visual items, A15-01 manifest, A15-04 notice, A09-02 corpus drift. Do a Dynamic Type and VoiceOver pass on the simulator.

## Phase D — Architecture and long-term
Break up `HouseScreen`; remove or isolate auth/sync dead code; unify frames and thresholds into shared definitions with parity tests; profile and fix proven performance hotspots; move test fixtures out of the app target; reconcile documentation with trimmed scope.

## Must-fix vs. worthwhile
**Must fix before submission:** A14-01, A14-02, X-02, confirmation of A08-01/02 and A02-01/02, submission paperwork (A16-01/02), demo AI plan (A16-03).
**Should fix:** X-01, A17-02/03, A12-02, A03-02, X-03, A10-03.
**Can wait:** everything in Phase D, performance (until profiled), iPad layouts, A01.

