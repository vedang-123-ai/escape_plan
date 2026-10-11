# 00 — Executive Summary

**Audit date:** 2026-10-11 · **Repo:** `Escape-Plan` (`escape_plan.xcodeproj`) · **Toolchain:** Xcode 27.0, iOS 27.0 simulator · **Nothing in the app was modified.** All reports are in this directory (00–21 + `_AUDIT_BRIEF.md`, `evidence/`). The older `audit/*.md` (2026-09-28) was left untouched.

> **Read this first — how much to trust it.** 18 investigators were launched; 17 finished. The Testing investigator failed three times on a quota error, so the lead did that domain (report 13, thinner). The iOS simulator runtime only appeared during the audit, so **most reports are source-based; runtime evidence is limited to a unit-test run and one launch screenshot.** The lead personally re-verified ~10 consequential findings (listed in report 19), and downgraded or rejected several agent ratings. Fire-safety content was checked online by one agent; the lead did not re-fetch sources and **no fire-safety professional has reviewed anything.**

## 1. What the app actually does today
A SwiftUI + SceneKit iOS app that builds a structured 3D model of a home (manual editor, optional LiDAR RoomPlan scan, demo homes) and, via a deterministic Python/FastAPI engine, computes escape routes per household member, hazard findings, a 0–100 readiness score and a checklist for fire, earthquake and severe weather. Fire routes are drawn on an animated 3D dollhouse with a fire-simulation playback; the app exports a printable PDF plan and an opt-in "responder snapshot" file; an assistant (Claude-backed, grounded in a 36-source cited corpus) explains results. Accounts/cloud sync are switched off for the demo. There is no location, notification or background functionality. (Sources: README, code inspection by Agents 1, 5, 8, 9.)

## 2. Verified vs. unverified
- **Verified by automated test:** iOS unit target 1150 passed / 0 failed / 3 skipped; backend 1258 passed / 1 skipped; EditorCore 656 passed (report 21).
- **Verified at runtime:** the app installs and launches on the iOS 27.0 simulator to an onboarding screen (screenshots in `evidence/screens/`). Nothing beyond that.
- **Verified by build:** the simulator build succeeds; the **Release device build fails** (A14-01).
- **Source-verified only:** nearly all user-journey, UI, accessibility, persistence and geometry findings.
- **Unverified / blocked:** UI tests, Instruments profiling, physical device and LiDAR scanning, live AI endpoints, real VoiceOver/Dynamic Type behaviour.

## 3. Strongest aspects
Deterministic routing/scoring engine kept separate from the AI (a credible answer to "is it an AI wrapper?"); large, fast, hermetic test suites; thoughtful safety framing (disclaimers, 911 first, "not a firefighter tool," consent for sharing; Agent 4's A04-07); privacy-conscious design choices (no location, EXIF stripped, names off by default); VoiceOver bridge for the 3D scene, Reduce Motion support, colour-blind-safe tokens (Agent 12); extensive documentation and decision log.

## 4. Most consequential defects (lead-adjudicated)
1. **Device/Release build is broken** (A14-01): `RoomCaptureController.swift:118`. Reproduced. The headline LiDAR feature cannot ship on a phone with this toolchain; hidden because every gate builds only for the simulator.
2. **Shared backend token ships inside the app bundle** (A14-02), confirmed in the build output.
3. **Cached score/hazards can be shown or exported without age or model match** (X-01).
4. **Backend 502/503 skips the offline route fallback** (X-02, agent-reported) — and a 502 is the documented state of the AI endpoints.
5. **Printed plan vs 3D view and scan converter appear mirrored** (A08-01/02) — by source reading, not yet compared visually.
6. Possible navigation trap on the "build manually" path (A02-01/02, source only).
7. Score explanation blames the wrong item when the structural cap applies (A17-03).
8. Submission paperwork gaps against Congressional App Challenge requirements (A16-01/02, per Agent 16 — re-check the official rules).

No finding was verified as CRITICAL for users' safety beyond A14-01's distribution blocker.

## 5. Safety-related claims and flows with thin support
- The app's disclaimers and scope are generally honest (Agents 4, 10). Weak points: a **one-time "monthly" alarm test** (X-03); **no carbon-monoxide guidance** (A04-03); the **printed plan omits in-fire rules** like feeling doors and staying low (A04-04); **stale scores** exported to responders (X-01). Egress-window thresholds and routing correctness were reviewed by agents but **need review by a fire-safety professional**, and the routing engine's correctness for real-world homes has only unit-level evidence.
- The app cannot determine that a house is safe, and the UI mostly avoids saying it can; the 0–100 score deserves a clear "guidance, not an inspection" label wherever it appears (verify on screens).

## 6. Reliability and architecture
Reliability: offline route caching exists and is a strength, but gateway errors and camera-permission denial are handled poorly (X-02, A10-03). Architecture: a 2,875-line `HouseScreen` holding ~45–59 state properties drives most architecture and performance concerns; zombie auth/sync code is retained after the demo trim; fixtures/mocks compile into the app target; tests symlinked via `tools/editorcore`. These are maintainability problems, not demo blockers; performance claims are **inferred, not profiled** (only a backend `/score` timing of ~1.2 s was measured).

## 7. What could undermine a live demo
Backend cold start on Render's free tier (42–52 s per Agent 16), AI endpoints returning 502 if credits are not restored, no device build until A14-01 is fixed, the LiDAR scan needing a physical LiDAR iPhone, an unverified navigation trap, and any mirrored-plan surprise.

## 8. Ten highest-priority improvements
1. Fix A14-01 and add a device-slice build to the gate. 2. Remove the token and internal docs from the bundle (rotate token). 3. Restore AI service or script a demo that works without it; pre-warm the backend. 4. Treat 502/503 as offline and label cached data age (X-02, X-01). 5. Compare PDF and 3D output on the simulator, then fix the transform (A08). 6. Run the UI on the simulator to confirm/repair navigation (A02). 7. Re-read the official CAC rules; fix the video script and contribution/AI disclosures. 8. Reword/fix the monthly alarm task; add CO guidance with expert review. 9. Fix VoiceOver access to failure-banner actions and the tab-bar occlusion. 10. Add privacy notice, privacy manifest and honest delete-account messaging.

## 9. Before submission vs. can wait
**Before submission:** items 1–7 and the report-20 "must fix" list. **Can wait:** `HouseScreen` refactor, removing dead auth/sync, iPad layouts, deep performance work, extra features.

## 10. Honest overall assessment (no numeric score — no defensible scoring method)
| Area | Assessment |
|---|---|
| Engineering quality | Solid logic core and tests; weak seam and device-slice coverage; very large view file. **Good, with known structural debt.** |
| Feature completeness | Broad and mostly integrated; trimmed features leave residue; device scan path currently uncompilable. **Strong for a student project, with release blockers.** |
| User experience | Polished-looking (screenshots, onboarding); several unverified navigation/layout risks. **Promising, not runtime-validated.** |
| Fire-safety information quality | Cited and cautious; gaps (CO, in-fire rules in PDF, monthly test) and no professional review. **Reasonable, needs expert review.** |
| Reliability | Good offline intent; gateway-failure and stale-cache gaps. **Fair; demo-sensitive to backend state.** |
| Accessibility | Better than typical (3D bridge, Reduce Motion); real gaps (banner, targets, contrast, editor). **Fair.** |
| Competition readiness | Clear problem, credible technical story; paperwork, demo reliability and device build are the risks. **Good potential; fix blockers and disclosures.** |

## 11. Report index
`01 architecture` · `02 SwiftUI` · `03 visual` · `04 fire-safety content` · `05 journeys` · `06 backend/APIs` · `07 persistence` · `08 location/geometry` · `09 notifications` · `10 reliability` · `11 performance` · `12 accessibility` · `13 testing (lead-written)` · `14 build/distribution` · `15 privacy` · `16 CAC readiness` · `17 consistency` · `18 independent review` · `19 cross-system` · `20 roadmap` · `21 test log`.

