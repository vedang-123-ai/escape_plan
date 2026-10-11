# Congressional App Challenge 2026 Readiness Audit

**Report Date:** 2026-10-11  
**Auditor:** Agent 16 (Competition Readiness & Verification Specialist)  
**Target Repository:** `Escape-Plan` (`escape_plan.xcodeproj`, `backend/`, `tools/editorcore`)  
**Evaluation Scope:** 2026 Congressional App Challenge (CAC) Official Rules Compliance, Claims Ledger Audit, Technical Substance, Demo Reliability, and Submission Materials Integrity.

---

## 1. Executive Summary

This audit assesses the readiness of the **Escape Plan** repository as an entry for the **2026 Congressional App Challenge (CAC)**. Verification was conducted on 2026-10-11 against official 2026 Congressional App Challenge published rules (`congressionalappchallenge.us`, `house.gov`), authoritative public safety standards (NFPA, FEMA, USFA, American Red Cross), repository source code, test suites, and project submission documentation.

### Core Verdict: Strong Technical Substance with Three Critical Submission-Level Action Items

Escape Plan is an exceptionally substantive, well-engineered, and disciplined entry that stands far above typical competition submissions. Rather than presenting a superficial "AI wrapper," the project implements a deterministic Python routing engine (Dijkstra shortest-path graph search, dynamic fire spread simulation, point-in-polygon object hazard checking) alongside an interactive SwiftUI + SceneKit 3D dollhouse editor and viewer. The safety domain guidance is meticulously anchored in a 36-source corpus from NFPA, FEMA, USGS, and the American Red Cross with automated server-side citation validation.

However, before the submission deadline (**12:00 PM EDT on October 26, 2026**), the team faces **three high-priority compliance and demo risks**:
1. **Demo Video Script Deficiencies (`script-v2.md`):** The current video narration draft completely omits participant names, a plain spoken target audience statement, and the specific programming languages and tools used. Under official 2026 CAC rules §4, these omissions risk scoring penalties or disqualification.
2. **Missing Individual Contribution Disclosure under Heavy AI Co-Authorship:** 513 of 634 non-merge git commits carry `Co-Authored-By: Claude` trailers. While the 2026 CAC rules permit AI development tools, they strictly require full disclosure and evidence that AI did not constitute the entirety of the project. The team has deferred the individual student contribution statement (`checklist.md:52`), leaving a critical compliance vulnerability unaddressed.
3. **Live AI Feature Failure (Anthropic Credits Depleted):** The Anthropic API account is currently unfunded (AUD-002), causing live calls to `/chat` and `/build` to fail with HTTP 502. Filming or demonstrating live AI will fail unless the account is funded, or the team enacts its documented fallback to cut Beat 5 from the video.

The deterministic features (routing, fire simulation, readiness scoring, checklist, 3D house editor, and sample homes) are completely decoupled from the AI backend, 100% operational, and verified across 1,258 automated backend tests and 656 EditorCore Swift tests.

---

## 2. Scope and Files Inspected

### Official Competition Sources Verified (Checked 2026-10-11)
- **Congressional App Challenge Official Rules & Guidelines:** `https://www.congressionalappchallenge.us/students/rules-and-process/` and `https://www.congressionalappchallenge.us/wp-content/uploads/2026/05/2026-CAC-Rules.pdf` (retrieved via search summaries and live fetches on 2026-10-11).
- **CAC Students Registration & Requirements Portal:** `https://www.congressionalappchallenge.us/students/` (retrieved live 2026-10-11).
- **U.S. House of Representatives CAC Information Pages:** `https://www.house.gov/` member guidance on CAC deadlines, video hosting, and eligibility.

### Repository Files Audited
- **Submission & Registration Docs:**
  - `docs/submission/checklist.md` (submission status tracker)
  - `docs/submission/app-description.md` (250-word written summary)
  - `docs/submission/written-answers-draft.md` (formal 6-question draft)
  - `docs/submission/what-we-learned.md` (retrospective & firefighter interview)
  - `docs/submission/judge-access.md` (judge deployment & evaluation strategy)
- **Demo & Presentation Materials:**
  - `docs/demo/script-v2.md` and `docs/demo/script-v1.md` (video narration script)
  - `docs/demo/storyboard-v2.md` and `docs/demo/storyboard-v1.md` (visual shot list)
  - `docs/demo/claims-ledger-v2.md` (public spoken claims vs. evidence)
  - `docs/demo/feature-inventory.md` (scope trim decisions)
- **Technical & Architectural Disclosures:**
  - `docs/tools-used.md` (exhaustive library, license, and AI disclosure)
  - `docs/ai-assistance/improved_prompt.md` (AI prompt transparency artifact)
  - `README.md` (primary public introduction)
  - `docs/tracker/BLOCKERS.md` (critical issue tracker)
- **Code & Test Implementation:**
  - `backend/app/routing/engine.py`, `egress.py`, `hazard.py`, `object_hazards.py`
  - `backend/app/scoring/score.py`, `checklist.py`
  - `backend/app/ai/chat/claims.py`, `backend/app/ai/chat/service.py`
  - `backend/corpus/sources.json`, `validate.py`
  - `escape_plan/Screens/HouseScreen.swift` (3D viewer, editor, simulation)
  - `escape_plan/Screens/AssistantScreen.swift` (AI chat UI)
  - `escape_plan/Capture/RoomCaptureSessionController.swift` (RoomPlan LiDAR)
  - `escape_plan/Export/ShareWithFireDepartmentCard.swift`, `ExportPlanDocument.swift`

---

## 3. Methods and Checks Performed

1. **Official Competition Rules Verification:** Web search and HTTP fetches of `congressionalappchallenge.us` and `house.gov` conducted on 2026-10-11. Verified strict requirements on student eligibility, team size, video length, hosting platform, and the updated 2026 AI disclosure policy.
2. **Claims Ledger Audit:** Traced each of the 16 spoken claims in `docs/demo/claims-ledger-v2.md` against real backend Python algorithms, iOS Swift views, schema definitions, and authoritative safety citations.
3. **Automated Test Suite Execution:**
   - Executed `python3 backend/corpus/validate.py` to confirm citation integrity across all 36 safety sources and 44 prevention tips.
   - Executed full non-live backend test suite: `PYTHONDONTWRITEBYTECODE=1 backend/.venv/bin/python -m pytest backend/tests/ -m "not live" -p no:cacheprovider` (1,258 passed, 1 skipped, 31 deselected, 0 failed).
   - Executed EditorCore macOS Swift test suite: `swift test --package-path tools/editorcore` (656 passed, 0 failed in 4.8s).
4. **Environment & Runtime Verification:** Checked local macOS Xcode and simulator availability via `xcrun simctl list runtimes` (iOS 27.0 installed; legacy iOS 26.5 unavailable). Noted simulator limitations in accordance with audit guidelines.
5. **Security & Secrets Inspection:** Verified `.gitignore` configuration for `escape_plan/BackendConfig.local.json` and evaluated bearer token / API credential handling.

---

## 4. Verified Official CAC Requirements vs. General Observations

To prevent inventing rubrics, the following table distinguishes verified requirements from official rules published on `congressionalappchallenge.us` (checked 2026-10-11) against general competition advice:

| Requirement Category | Verified Official CAC 2026 Rule (Cited Source) | General Observation / Advisory Practice |
|---|---|---|
| **Deadline** | **October 26, 2026 at 12:00 PM (noon) EDT** (`2026 CAC Rules §5`). Submissions close strictly. | The team's internal target of October 24 (`checklist.md:11`) provides a healthy 48-hour buffer. |
| **Eligibility** | Middle or high school student at submission date; U.S. resident; maximum 4 students per team; at least 50% residing or attending school in the submitting district (`2026 CAC Rules §1, §2`). | Owner confirmed eligibility on 2026-10-05 (`checklist.md:18-24`). |
| **Prior Work Cutoff** | App must be created after **October 30, 2025** (`2026 CAC Rules §3`). | Project inception was 2026-07-10 (verified by git history). Fully compliant. |
| **Demo Video Length** | **1 to 3 minutes** (maximum 3:00) (`2026 CAC Rules §4`). Exceeding 3:00 can trigger disqualification/penalties. | `script-v2.md` timed at ~2:04 (311 words). Fully within length constraints. |
| **Demo Video Hosting** | Must be hosted on a public video site (e.g., YouTube or Vimeo) set to **Public** (`2026 CAC Rules §4`). | Unlisted or private video links are explicitly invalid under CAC rules. |
| **Demo Video Mandatory Content** | Must include: (1) Names of all participants, (2) Name of the app, (3) Purpose in one sentence, (4) Target audience, (5) Tools and coding languages used, (6) Demonstration of how the app works (`2026 CAC Rules §4`). | `script-v2.md` currently fails items 1, 4, and 5 (see Finding 16-01). |
| **AI Usage & Disclosure** | AI tools are allowed if: (1) fully disclosed in submission materials, (2) AI does not constitute the entirety of technical development, and (3) students demonstrate significant individual contributions and technical understanding (`2026 CAC Rules §3`). | Disclosures in `docs/tools-used.md` are excellent, but individual student contribution statements remain blank (`checklist.md:52`). |
| **Judges' Access** | Judges primarily evaluate video and written answers (`Rules §7.1`), but have the right to request access to the app and source code in person or via reasonable manner (`Rules §7.3`). Failure to honor request results in disqualification. | Solved via public GitHub repository, local simulator build instructions, and live device demonstrations over video call (`judge-access.md`). |

---

## 5. Findings (with Evidence)

### [HIGH] 16-01 Demo Video Script Omits Mandatory Official Disclosures
**Domain:** Competition Rules Compliance  
**Location:** `docs/demo/script-v2.md:1-51` / Demo Video Production  
**Observed behavior:**  
The demo video narration script (`script-v2.md`) omits three mandatory elements explicitly required by official Congressional App Challenge rules:
1. It does not introduce the names of the student participants.
2. It lacks a plain, explicit spoken statement of who the app is for (target audience), relying solely on implicit context ("about a quarter of families").
3. It does not state the tools and programming languages used to build the app (Swift, SwiftUI, SceneKit, Python, FastAPI).

**Evidence:**  
Official 2026 CAC Rules §4 ("Demonstration Video") mandates:
> "The Demonstration Video should include... The name(s) of the participant(s)... The name of the app... The purpose of the app in one clear sentence... Who the app is intended for... The tools and coding languages used... A demonstration of how the app works."

In `docs/demo/script-v2.md`, lines 13–19 (Beat 1) start directly with:
```markdown
## Beat 1 — Hook
> **VO:** When a smoke alarm goes off, you may have as little as two minutes to get out... So we built Escape Plan.
```
Furthermore, `docs/submission/checklist.md` lines 31, 34, 35 specifically confirms this omission:
```markdown
| Says the name of each participant | PERSON | Not in script-v2.md yet (BLOCKERS, S11.51) |
| Says who the app is for (target audience) | PERSON | Not stated plainly in script-v2.md (BLOCKERS, S11.51) |
| Says the tools and coding languages used | PERSON | Not in script-v2.md (BLOCKERS, S11.51) |
```
**Expected behavior:**  
The demo video narration or title slate must explicitly state the students' names, state "We built Escape Plan for families, especially households with young children, older relatives, or mobility limitations," and state "Built using Swift, SwiftUI, and SceneKit on iOS, with a custom Python routing engine."  
**Root cause:**  
The script was trimmed aggressively for dramatic pacing and storytelling economy (targeting ~2 minutes) without restoring the mandatory rulebook checklist items.  
**Impact:**  
Evaluators using the official CAC evaluation sheet can deduct points or flag non-compliance for missing mandatory video elements.  
**Recommended improvement:**  
Add a 10-second spoken intro or concise on-screen visual title card covering:
- Names: "Hi, we are Vedang, Anish, and Yuki..."
- Audience: "...and we created Escape Plan for families to prepare before an emergency."
- Stack: "Built in Swift, SwiftUI, SceneKit, and Python."  
**Dependencies:** Final filming pass (S11.13).  
**Verification status:** Verified by source inspection.  
**Confidence:** High  
**Effort:** Small (script adjustment).

---

### [HIGH] 16-02 Missing Individual Technical Contribution Statement Under Extensive AI Commit History
**Domain:** Originality & Academic Integrity Compliance  
**Location:** `docs/tools-used.md:123-143`, `docs/submission/checklist.md:52`, `docs/submission/written-answers-draft.md:120-123`  
**Observed behavior:**  
The repository reflects extensive use of AI coding assistants (513 of 634 non-merge commits carry a `Co-Authored-By: Claude` trailer, and 22 commits are authored directly by "Claude"). The submission checklist item for "A statement of each member's own contribution and understanding" remains marked `PERSON (deferred)` and has not been drafted.  
**Evidence:**  
`docs/submission/checklist.md:52`:
```markdown
| A statement of each member's own contribution and understanding | PERSON (deferred) | Owner deferred this on 2026-10-05 and will decide later. The rules: AI "must not constitute the entirety of the technical development". 513 of 634 non-merge commits carry a Claude co-author line, so this sentence matters (BLOCKERS, S11.51) |
```
`docs/submission/written-answers-draft.md:120-122`:
```markdown
> **For the team to finish before pasting:** add one or two sentences in your own words on what each of you personally designed, decided, built or checked. The rules expect "significant individual contributions and technical understanding", and only you can state that.
```
Official 2026 CAC Rules §3 ("App Parameters") state:
> "The app must be original and solely created by the student or team... While participants may use open-source libraries, frameworks, and external tools, they must clearly document any such usage... AI tools are permitted provided that... AI is used only to support specific aspects of the project and does not constitute the entirety of the technical development... You demonstrate significant individual contributions and technical understanding of the app."
**Expected behavior:**  
Every student team member must provide a precise, truthful personal summary detailing the specific modules, algorithms, UI screens, tests, or design decisions they formulated and validated.  
**Root cause:**  
The team prioritized engineering sessions and deferred writing personal narrative statements until the final submission portal entry.  
**Impact:**  
A judge or congressional reviewer reviewing the public GitHub repository could perceive the project as largely AI-generated if the students fail to articulate their personal technical ownership and conceptual command.  
**Recommended improvement:**  
Immediately draft and review the individual contribution section in `written-answers-draft.md`, documenting each member's specific responsibilities (e.g., routing algorithm design, SceneKit visualization, firefighter interview/prevention pivot, corpus compilation, and test engineering).  
**Dependencies:** Student team members.  
**Verification status:** Verified by source inspection.  
**Confidence:** High  
**Effort:** Small (writing task).

---

### [HIGH] 16-03 Live AI Features Fail with HTTP 502 Due to Depleted Anthropic Credits
**Domain:** Demo Reliability & Backend Functionality  
**Location:** `docs/tracker/BLOCKERS.md:82` (AUD-002), `backend/app/ai/chat/service.py:120`, `docs/demo/script-v2.md:46-51`  
**Observed behavior:**  
The Anthropic API account powering Claude has exhausted its credits. At runtime, live calls to `/chat` (Assistant tab) and `/build` (Import Plan) fail and return HTTP 502 Bad Gateway. In `script-v2.md`, Beat 5 explicitly showcases the AI Assistant.  
**Evidence:**  
`docs/tracker/BLOCKERS.md:82`:
```markdown
- [ ] AUD-002 (P1) Anthropic credits · owner, not yet (2026-09-29); S11.49 verifies live
```
`docs/submission/checklist.md:38,72`:
```markdown
| The AI assistant is shown only if the Anthropic account is funded and preflight passes | BLOCKED | Credits are out (BLOCKERS AUD-002). Otherwise cut Beat 5 (decisions 2026-10-04, S11.12) |
- Live AI behaviour (assistant, Import Plan). Verified in stub tests only; the account is out of credits.
```
`docs/demo/script-v2.md:46-51`:
```markdown
## Beat 5 — Grounded AI
> **VO:** Finally, we included an AI assistant to chat about your home and explain safety tips...
```
**Expected behavior:**  
Either the API account is funded and verified against live queries, or Beat 5 is excised from the video recording to prevent presenting non-working functionality.  
**Root cause:**  
Developer API billing depletion during the active development and audit arc.  
**Impact:**  
If the team attempts to film Beat 5 on a live phone without funded credits, the UI displays backend error banners. If a judge requests access and tries the Assistant tab, it fails.  
**Recommended improvement:**  
Execute one of two unambiguous paths:
- **Path A:** Fund the Anthropic account ($5–$10), run `python3 scripts/demo-preflight.py`, and verify live `/chat` responses.
- **Path B:** Follow the pre-agreed fallback: delete Beat 5 from `script-v2.md`, remove the AI paragraph from `docs/submission/app-description.md`, and hide or leave the Assistant tab as an unfeatured extra.  
**Dependencies:** Repository owner / account holder.  
**Verification status:** Verified by source inspection.  
**Confidence:** High  
**Effort:** Small ($5–$10 top-up or script cut).

---

### [MEDIUM] 16-04 Render Free Tier Cold-Start Latency (42–52s) Endangers Live Demonstration
**Domain:** Live Evaluation Reliability & Infrastructure  
**Location:** `render.yaml:8-12`, `docs/submission/judge-access.md:28-30`  
**Observed behavior:**  
The production backend is hosted on Render's free web service tier. When inactive for >15 minutes, Render spins the container down. The first subsequent HTTPS request incurs a 42- to 52-second cold-start spin-up delay.  
**Evidence:**  
`docs/submission/judge-access.md:28-30`:
```markdown
The server runs on Render's free plan at https://escape-plan-backend.onrender.com. The first call after it sleeps took 42 to 52 seconds in our tests. Every call except /health needs a shared password (the "bearer token").
```
`docs/submission/judge-access.md:66`:
```markdown
Wake the server first: open https://escape-plan-backend.onrender.com/health a minute before.
```
**Expected behavior:**  
Interactive API requests (`/routes`, `/score`) respond within <1.5 seconds during a demonstration.  
**Root cause:**  
Free-tier container lifecycle on Render.  
**Impact:**  
If a judge evaluates the app live (via video call or local test) and taps "Calculate Routes" or "Score," the app appears unresponsive or frozen for nearly a minute, risking the impression of a crashed or broken app.  
**Recommended improvement:**  
1. Document an explicit operational protocol in `docs/submission/judge-access.md`: ping `GET /health` 2 minutes prior to any scheduled evaluation or video recording.
2. Optionally upgrade the Render instance to the $7/month Starter plan for October 2026 to ensure 24/7 warm availability.  
**Dependencies:** Render account owner.  
**Verification status:** Verified by source inspection & benchmark logs.  
**Confidence:** High  
**Effort:** Small.

---

### [MEDIUM] 16-05 Bearer Token Architecture Creates Obstacles for Independent Source Code Builds
**Domain:** Judge Code Evaluation & Reproducibility  
**Location:** `escape_plan/Networking/APIClient.swift:75-95`, `docs/submission/judge-access.md:85-94`  
**Observed behavior:**  
All backend API routes (except `/health`) require an HTTP `Authorization: Bearer <token>`. In the iOS project, `escape_plan/BackendConfig.local.json` contains this token and is deliberately gitignored for security. When judges clone the proposed public repository and build in Xcode, the app has no valid bearer token for the deployed Render server.  
**Evidence:**  
`docs/submission/judge-access.md:85`:
```markdown
A judge building from the repo has no token, and should not get the real one. Two ways, best first:
1. Run the server on the same Mac with any password they choose...
2. If a judge cannot run Python, a teammate can send them the real token privately...
```
`escape_plan/Networking/APIClient.swift:80-92`:
```swift
if let path = Bundle.main.path(forResource: "BackendConfig.local", ofType: "json") { ... }
```
**Expected behavior:**  
Judges inspecting or building the code from GitHub can easily test the app without getting 401 Unauthorized errors on core features.  
**Root cause:**  
Necessary defense against unauthorized traffic and API scraping on a public server.  
**Impact:**  
Non-technical judges attempting to compile and run the app in Xcode will find routing and scoring inoperative unless they also run the Python server locally or enter a provided token in Debug Settings.  
**Recommended improvement:**  
Ensure the repository `README.md` features prominent, step-by-step instructions for judges on running the local Python backend with `BACKEND_BEARER_TOKEN`, or clearly direct judges to request a live demo over Zoom/FaceTime as outlined in `judge-access.md` §3.  
**Dependencies:** Documentation in `README.md`.  
**Verification status:** Verified by source inspection.  
**Confidence:** High  
**Effort:** Small.

---

### [LOW] 16-06 Potential Multi-Peril Presentation Misalignment (Fire-Only Routing)
**Domain:** Claims Ledger & Marketing Accuracy  
**Location:** `docs/demo/claims-ledger-v2.md:10,15`, `README.md:5-8`, `escape_plan/Screens/HouseScreen.swift:6-10`  
**Observed behavior:**  
Escape Plan calculates and animates evacuation routes exclusively for **fire**. Earthquake and severe weather (tornado) features are restricted to the preparedness score deduction breakdown and the Tasks checklist. Earlier draft documentation occasionally blurred this distinction.  
**Evidence:**  
`docs/demo/claims-ledger-v2.md:10`:
```markdown
| 6 | "primary fire escape route, and a secondary route through a different exit" | VERIFIED (fire only) | Routing engine; NFPA two-ways-out logic. The app draws fire routes only: House sends no `peril` and `/routes` defaults to fire; earthquake and tornado plans exist in the backend but no screen shows them (S53-3, decisions 2026-10-05) |
```
`docs/demo/claims-ledger-v2.md:15`:
```markdown
| 11 | "readiness score and a checklist for fire, earthquakes, and tornadoes" | VERIFIED | Score screen, `ScoreModels.swift`. Score and Tasks only: never say the app draws earthquake or tornado routes or shelters |
```
`escape_plan/Readiness/ScoreBasisLabel.swift:18-28`:
Fire is labeled "Code-quantified", while earthquake and tornado are labeled "Guidance-based".  
**Expected behavior:**  
All marketing text, demo voiceovers, and written answers must consistently maintain that the 3D dollhouse animates *fire* routes only, while earthquake and tornado preparedness are delivered via checklist and scoring.  
**Root cause:**  
Natural evolution of project scope where routing was originally scoped for multi-perils but appropriately locked to fire to maintain rigorous code-compliance.  
**Impact:**  
Low, provided `script-v2.md` and `app-description.md` continue their current honest phrasing.  
**Recommended improvement:**  
Audit the final spoken video cut to ensure no inadvertent claims suggest 3D animated tornado or earthquake evacuation routing.  
**Dependencies:** Demo video recording.  
**Verification status:** Verified by source inspection.  
**Confidence:** High  
**Effort:** Small.

---

### [LOW] 16-07 LiDAR Hardware Requirement Mitigated by Sample Homes and Manual Editor
**Domain:** Hardware Accessibility & Evaluation Experience  
**Location:** `escape_plan/Capture/RoomCaptureSessionController.swift:24`, `schema/fixtures/`  
**Observed behavior:**  
The RoomPlan LiDAR room capture capability requires physical iOS hardware equipped with a LiDAR sensor (iPhone 12+ Pro or iPad Pro). In the iOS Simulator, `RoomCaptureSession.isSupported` returns `false`, preventing live scanning during evaluation on a Mac.  
**Evidence:**  
`docs/submission/judge-access.md:37-43`:
```markdown
| Works in the Simulator | Does not |
| Built-in sample homes (fresh install has four) | LiDAR scanning (RoomPlan needs a LiDAR iPhone or iPad) |
| The 3D House view and full editor | The AI assistant (needs credits) |
```
**Expected behavior:**  
Judges evaluating without a LiDAR device must have access to functional, realistic test environments.  
**Root cause:**  
Hardware constraint of Apple RoomPlan technology.  
**Impact:**  
Minimal, because the app bundles 4 complete sample homes (`bungalow.json`, `twostory.json`, `apartment.json`, `multilevel.json`) and provides a full manual 3D floor plan editor with undo/redo.  
**Recommended improvement:**  
No code change required. In the demo video, ensure the narration explicitly clarifies: "You scan your home with an iPhone's LiDAR sensor, or choose from pre-built homes and draw it in the 3D editor."  
**Dependencies:** None.  
**Verification status:** Verified by source inspection.  
**Confidence:** High  
**Effort:** None.

---

## 6. Claims Ledger Audit: Spoken Claims vs. Verified Implementation

The 16 spoken claims in `docs/demo/claims-ledger-v2.md` were cross-checked against actual code implementation, test suites, and authoritative standards:

| Claim # | Spoken Claim in Script | Audit Status | Code / Source Verification Evidence |
|---|---|---|---|
| **1** | *"as little as two minutes to get out"* | **VERIFIED** | NFPA / American Red Cross standard. Cited in `backend/corpus/sources.json` (`redcross-two-minutes`) and FEMA USFA residential fire research. Checked 2026-10-11. |
| **2** | *"about a quarter of families have made and practiced an escape plan"* | **VERIFIED** | American Red Cross survey data (26%). Cited in `backend/corpus/sources.json` (`redcross-escape-fact-sheet`). Checked 2026-10-11. |
| **3** | *"scan your home, and it builds a 3D model"* | **VERIFIED** | `escape_plan/Capture/RoomCaptureSessionController.swift`, `backend/app/convert/engine.py`. Produces valid Schema 2.1 home models. |
| **4** | *"gets us most of the way there... never perfect"* | **VERIFIED** | Invariant in schema and converter: room geometries preserve confidence flags rather than dropping imprecise walls. |
| **5** | *"full 3D editor... fix any mistakes"* | **VERIFIED** | `HouseScreen.swift` (2,876 lines). Full manipulation of walls, doors, windows, stairs, furniture. Verified by 656 passing EditorCore tests. |
| **6** | *"primary fire escape route, and a secondary route through a different exit"* | **VERIFIED (Fire Only)** | `backend/app/routing/egress.py` & `engine.py`. Implements NFPA two-ways-out logic. Fire routes only. |
| **7** | *"deterministic engine we wrote"* | **VERIFIED** | `backend/app/routing/` (pure Python Dijkstra & geometry, zero third-party graph/solver libraries). 1,258 pytest cases pass. |
| **8** | *"fire drill simulation... watch everyone reroute"* | **VERIFIED** | `HouseScreen.swift:650-800` & `backend/app/routing/hazard.py`. Dynamic fire spread with playhead, speed control (0.25x-2x), and rerouting. |
| **9** | *"flags object hazards, warning you if furniture narrows a path"* | **VERIFIED** | `backend/app/routing/object_hazards.py`. Computes oriented-box geometry and clear egress width thresholds. |
| **10** | *"working firefighter... pointed us toward prevention"* | **VERIFIED** | Firefighter interview documented in `docs/playbook/01-product-spec.md` §2 and `docs/submission/what-we-learned.md`. Real pivot away from tactical response. |
| **11** | *"readiness score and a checklist for fire, earthquakes, and tornadoes"* | **VERIFIED** | `backend/app/scoring/score.py` & `checklist.py`. Produces 0-100 composite readiness score with category breakdown. |
| **12** | *"fire module is fully quantified... earthquake and tornado use FEMA and NOAA guidance"* | **VERIFIED** | `escape_plan/Readiness/ScoreBasisLabel.swift`. Explicit distinction: fire uses building-code dimensions; perils use guidance. |
| **13** | *"share a snapshot of your plan with your local fire department"* | **VERIFIED** | `escape_plan/Export/ShareWithFireDepartmentCard.swift`. Generates structured opt-in summary sheet with explicit consent modal. |
| **14** | *"AI assistant to chat about your home"* | **UNVERIFIED LIVE (Needs Credits)** | UI exists (`AssistantScreen.swift`) and backend exists (`backend/app/ai/chat/`), but returns HTTP 502 live due to unfunded Anthropic account. |
| **15** | *"Every safety answer is grounded... cites its source... if it can't back something up, it says so"* | **VERIFIED BY TEST ONLY** | Grounding regex and deferral logic verified in `backend/tests/test_chat.py`. Never verified against live LLM model at runtime. |
| **16** | *"AI explains, but it never computes a route"* | **VERIFIED** | Clean architectural boundary: `backend/app/routing/` has zero dependencies on Claude, OpenAI, or LLMs. |

---

## 7. Positive Findings & Engineering Strengths

1. **Deterministic Core Algorithmics:** Unlike many contemporary student submissions that outsource core intelligence to LLM prompts, Escape Plan implements its routing, fire spread, and object-hazard spatial collision logic entirely in pure, deterministic Python code. It is immune to hallucinations and reproducible on every run.
2. **Honesty About Safety Limitations:** The app and documentation exhibit commendable safety ethics. Rather than presenting pseudo-scientific evacuation routes for earthquakes or tornadoes, the project strictly limits routing to fire (governed by NFPA/IRC standards) and clearly labels earthquake and tornado features as "Guidance-based" tasks.
3. **Ruthless and Disciplined Scope Pruning:** The engineering team demonstrated remarkable maturity by cutting high-risk, fragile features (AR camera walkthrough, Vision ML object detection, and cloud account synchronization) prior to submission. This eliminates points of failure during judging.
4. **Deep Accessibility Implementation:** `escape_plan/Screens/HouseScreen.swift` contains a dedicated `HouseSceneAccessibility` enum (lines 2641–2680) that translates 3D SceneKit spatial simulations into structured, spoken VoiceOver narration (elapsed time, rooms untenable, individuals overtaken, and numbered step-by-step route directions). WCAG contrast ratios are enforced in `Theme.swift`.
5. **Zero Third-Party iOS Dependencies:** The iOS app imports zero external CocoaPods, Carthage packages, or remote Swift Package dependencies. It relies 100% on native Apple SDK frameworks (SwiftUI, SceneKit, RoomPlan).

---

## 8. Systemic Issues and Root Causes

- **Relying on "Deferred" Tasks at Project Closeout:** The team maintained an excellent engineering cadence with AI coding agents, but deferred non-coding human tasks (individual student contribution statements, video voiceover recording, and paid developer account enrollment) to the final days before submission.
- **External API Billing Fragility:** Tying an AI feature to a paid third-party API without automated credit monitoring created an operational blind spot where the assistant silently broke once development credits were exhausted.
- **Free-Tier Cloud Infrastructure Limits:** Hosting on Render's free tier provides $0 operational cost but introduces cold-start latency that directly conflicts with live, on-demand judge evaluation.

---

## 9. Unverified Assumptions

1. **Judge Device & Xcode Configuration:** Assumed judges requesting code access will possess a Mac running Xcode 16+ and Python 3.11+. In practice, many congressional staff or local judges will not have development environments.
2. **Apple Developer Program Enrollment:** Assumed TestFlight is optional. If congressional judges in the specific district request an iOS installation rather than a video or live Zoom demo, lack of TestFlight would force manual ad-hoc or local Mac builds.
3. **Live AI Safety Guardrails Under Real Model Latency:** The server's citation-retry mechanism was verified in unit test mocks (`test_chat.py`), but has not been measured under live Claude API timeouts or streaming constraints.

---

## 10. Areas Requiring Further Investigation

1. **Submitting Congressional District Host Status:** The owner verified the district is participating (`checklist.md:20`), but the team should double-check the specific representative's local rules (some offices establish district-specific presentation formats or regional award ceremonies).
2. **Repository Visibility & Scrubbing:** Prior to making `vedang-123-ai/escape_plan` public on GitHub, the team must confirm that no commit messages or activity logs contain personal phone numbers, physical home addresses, or credentials (as identified in `BLOCKERS.md` S11.55 findings).

---

## 11. Recommended Priorities & Action Plan

### Tier 1: Immediate Submission Gate (Before October 24, 2026)
1. **Revise `script-v2.md` Narration:** Add the required 10-second opening: participant names, explicit target audience ("families preparing before an emergency"), and programming languages ("Swift, SwiftUI, SceneKit, and Python").
2. **Complete Individual Student Contribution Disclosures:** In `docs/submission/written-answers-draft.md`, draft 1–2 specific sentences for each team member detailing their personal technical contributions to satisfy the CAC AI policy.
3. **Resolve AI Assistant Strategy (Fund vs. Cut Beat 5):** Either add $5 in Anthropic credits to enable live `/chat`, or cleanly cut Beat 5 from the video script and remove the AI paragraph from `docs/submission/app-description.md`.

### Tier 2: Pre-Demo & Judge Reliability (Week of Submission)
4. **Execute Device Video Recording:** Record the final cut on the physical iPhone 17 Pro, ensuring no debug banners or settings menus appear. Verify the completed video is between 1:00 and 3:00 and uploaded as **Public** on YouTube.
5. **Make Repository Public & Harden README:** Make the GitHub repo public, verify secret scanning is enabled, and ensure `README.md` clearly guides evaluators to run the local server or request a live video demonstration.
6. **Pre-Warm Production Backend for Live Inquiries:** Keep `https://escape-plan-backend.onrender.com/health` bookmarked to wake the server 2 minutes prior to any live interview or judging session.
