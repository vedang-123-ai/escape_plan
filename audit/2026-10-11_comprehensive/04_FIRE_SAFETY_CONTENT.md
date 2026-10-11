# Domain Audit Report: Fire Safety Content, Checklists, and Guardrails

**Audit Domain:** Fire Safety Content, Guidance, Rules, Thresholds, Scoring, and AI Guardrails  
**Auditor:** Agent 4 (Senior Safety & Compliance Engineer)  
**Date:** 2026-10-11  
**Target Repository:** Escape Plan iOS App & Backend  
**Output Report:** `audit/2026-10-11_comprehensive/04_FIRE_SAFETY_CONTENT.md`

---

## 1. Executive Summary

This audit evaluates the safety integrity, technical correctness, authoritative grounding, and presentation consistency of all user-facing safety instructions, checklist items, prevention tips, hazard thresholds, scoring formulas, and AI chat guardrails across the Escape Plan repository.

### Key Takeaways
1. **Strong Grounding Core:** The core fire safety principles, egress dimensions (IRC R310), object clearance rules (NFPA 3-foot heater clearance), natural hazards protective actions (Drop, Cover, and Hold On; tornado interior shelter hierarchy), and emergency protocol (get out first, call 911 from outside, never re-enter) are firmly grounded in authoritative literature from the USFA, NFPA, ICC, American Red Cross, USGS, and NOAA/NWS.
2. **Critical Flaw in Monthly Alarm Testing Recurrence (A04-01):** On 2026-10-05, the backend and frontend were modified so that `alarm.test_monthly` ceased recurring. Ticking "Test every smoke alarm this month" once marks it permanently complete in perpetuity. The task never re-opens, contradicting the explicit safety claim and USFA/NFPA maintenance mandates.
3. **Double-Counting Level Alarms (A04-02):** The deterministic checklist generator unconditionally emits an alarm requirement for every floor *in addition to* emitting an alarm requirement outside sleeping areas on that same floor. On standard single-story homes or bedroom floors, this requires two hallway alarms where code requires one, inappropriately docking preparedness points.
4. **Complete Omission of Carbon Monoxide Safety (A04-03):** Despite defining `co_detector` in the schema and data models, the app contains zero checklist items, rules, or scoring deductions for CO alarms, despite mandatory requirements in the IRC (§R315) and NFPA 720 / 72 for homes with fuel-burning appliances or attached garages.
5. **Printable PDF Omits Essential In-Fire Survival Rules (A04-04):** The printable refrigerator escape plan generates geometric room-by-room routes and an outside meeting place, but omits standard life-safety reminders (feeling doors for heat, crawling under smoke, closing doors behind you) that every standard NFPA/Red Cross escape plan template includes.
6. **Exemplary Tactical & Emergency Disclaimers:** The application maintains consistent, unambiguous disclaimers across onboarding, export screens, responder snapshots, and AI system prompts, explicitly warning that the app is an educational prevention/readiness snapshot and must never be used mid-fire by residents or first responders.

---

## 2. Scope and Files Inspected

Every file containing safety copy, thresholds, scoring logic, AI instructions, or export narration was inspected in full:

### iOS Application (Swift & Bundled Resources)
- `escape_plan/Resources/prevention_tips.json`: 36 user-facing prevention tips covering fire, earthquake, and tornado.
- `escape_plan/Readiness/PreventionTip.swift`: Swift data model for prevention tips.
- `escape_plan/Readiness/PreventionTipsFilter.swift`: Deterministic filtering and spotlight selection logic.
- `escape_plan/Readiness/LoadingTipRotator.swift`: Random shuffle bag front-loading fire tips (75% weight).
- `escape_plan/Readiness/ScoreBand.swift`: Preparedness score tier definitions ("Well prepared", "Some gaps to close", "Needs work").
- `escape_plan/Readiness/ScoreBasisLabel.swift`: UI presentation of "Code-quantified" vs. "Guidance-based" tiers.
- `escape_plan/Export/RouteNarration.swift`: Pure plain-English translation of engine routes, step numbering, and findings.
- `escape_plan/Export/EscapePlanPDF.swift`: Vector PDF generator for printable escape plans and Responder Snapshots.
- `escape_plan/Export/ResponderSnapshotJSON.swift`: Machine-readable snapshot model, disclaimers, and consent schema.
- `escape_plan/Export/SnapshotHazardSummary.swift`: Deterministic roll-up of engine hazard findings.
- `escape_plan/Export/ShareWithFireDepartmentCard.swift`: Opt-in fire department share card and disclaimers.
- `escape_plan/Screens/ConsentSheet.swift`: Multi-point consent sheet and tactical limitations warning.
- `escape_plan/Screens/HomeScreen.swift`: Home tab layout, "Prevent" card spotlight, "Up next" task preview, fire drill launcher.
- `escape_plan/Screens/ScoreScreen.swift`: Preparedness score breakdown, sub-scores, basis labels, largest deduction row.
- `escape_plan/Screens/TasksScreen.swift`: Readiness checklist issue list, urgency groups, recurrence notices.
- `escape_plan/Screens/TaskComponents.swift`: Task status icons, detail sheet, source citation rows.
- `escape_plan/Onboarding/OnboardingFlowView.swift`: Household onboarding interview, profile capture, safety copy.
- `escape_plan/Models/ScoreModels.swift`: Swift mirror of `/score` contract, checklist items, and recurrence handling.
- `escape_plan/Models/RoutePlan.swift`: Swift mirror of `/routes` contract, finding kinds, and routing constraints.
- `escape_plan/Models/Enums.swift`: Core schema enums (`RoomType`, `OpeningKind`, `ObjectCategory`, `Equipment`, `ProfileTag`).

### Backend (Python, Markdown Corpus & Configuration)
- `backend/corpus/sources.json`: Master index of 28 citable external sources and 13 compiled markdown documents.
- `backend/corpus/validate.py`: Validation suite for corpus integrity, citations, and unit conversions.
- `backend/corpus/check_urls.py`: URL verification and keyword testing script.
- `backend/corpus/egress_thresholds.json`: IRC Section R310 and R311 code thresholds.
- `backend/corpus/object_hazard_thresholds.json`: Cited NFPA clearances and engineering constants.
- `backend/corpus/prevention_tips.json`: Canonical prevention tips library.
- `backend/corpus/smoke-alarms-usfa.md`: Smoke alarm placement, testing, replacement, and death rate statistics.
- `backend/corpus/escape-planning-nfpa.md`: NFPA two-ways-out, meeting place, practice cadence, and extinguisher decision rules.
- `backend/corpus/home-fire-escape-redcross.md`: Red Cross two-minute benchmark, drill procedures, and fast facts.
- `backend/corpus/fire-facts-stats.md`: Fire statistical baselines and casualty reduction figures.
- `backend/corpus/egress-windows-irc.md`: Detailed analysis of IRC R310 opening dimensions and net clear area.
- `backend/corpus/heating-electrical-fire-safety.md`: Space heaters, cooking grease fires, electrical cords, dryer lint, lithium batteries.
- `backend/corpus/special-considerations.md`: Children, older adults, mobility impairments, deaf/hard-of-hearing, and pets.
- `backend/corpus/earthquake-preparedness.md`: Drop, Cover, and Hold On; situation-specific actions; debunked myths.
- `backend/corpus/earthquake-securing-home.md`: Moving before fastening, water heater strapping, Northridge UCLA statistics.
- `backend/corpus/earthquake-after-shaking.md`: Gas shutoff conditional rule, post-shaking hazards, evacuation criteria.
- `backend/corpus/severe-weather-tornado.md`: Shelter hierarchy, interior rooms, head protection, vehicle/outdoor rules.
- `backend/corpus/tornado-safe-rooms.md`: FEMA P-361/P-320 criteria vs. conventional construction wind speeds.
- `backend/corpus/tornado-warnings-and-mobile-homes.md`: Watches vs. warnings, mobile homes, NOAA Weather Radio SAME alerting.
- `backend/app/scoring/checklist.py`: Deterministic checklist item generation, recurrence rules, and severity levels.
- `backend/app/scoring/score.py`: Preparedness composite and sub-score scoring algorithm, caps, and deductions.
- `backend/app/routing/object_hazards.py`: Geometric hazard analysis for topple, overhead, and heat clearance.
- `backend/app/ai/chat/service.py`: Claude chat service, system prompt `CHAT_RULES`, and citation retry loop.
- `backend/app/ai/chat/claims.py`: Deterministic classifier for uncited safety claims and imperative verbs.

---

## 3. Methods and Checks Performed

1. **Static Analysis & Full File Review:** Traced every user-facing string from data storage/generation to UI display.
2. **Authoritative Fact-Checking via Web:** Verified every safety claim against official technical documentation from USFA, FEMA, NFPA, American Red Cross, ICC (IRC), USGS, NOAA/NWS, and California legislative statutes on 2026-10-11.
3. **Cross-System Consistency Audit:** Compared iOS Swift mirror strings and JSON resources with backend corpus and Python generation logic to detect divergence.
4. **Scope & Disclaimer Integrity Analysis:** Analyzed whether UI language could mislead users into believing the app calculates structural building safety, active fire paths, or emergency responder tactical routing.
5. **Code & Formula Verification:** Audited the metric/imperial conversion fidelity in `egress_thresholds.json` and `object_hazard_thresholds.json`.

---

## 4. Findings (with Evidence)

### A04-01: [HIGH] Smoke Alarm Monthly Testing Ceased Recurrence and Stays Permanently Done on First Tick
**Domain:** Fire Safety / Checklist & Scoring  
**Location:** `backend/app/scoring/checklist.py:65, 204-218`, `escape_plan/Models/ScoreModels.swift:205-227`  
**Observed behavior:** `alarm.test_monthly` was changed on 2026-10-05 from a recurring 30-day task to a permanent one-time completion (`FORMERLY_RECURRING_IDS`). Once ticked, it is marked `done: true` permanently and never re-opens.  
**Evidence:**
- In `backend/app/scoring/checklist.py:204-210`:
  ```python
  #: Items that once recurred (S11.34) and are now one-time ticks. The monthly alarm
  #: test stopped recurring on 2026-10-05 (owner's product choice, docs/decisions.md):
  #: ticked once is done for good, it never lapses and never lowers the score. Its
  #: cited text still says to test monthly. Phones from before the change stored a
  #: completion date for it, so ANY string value counts as done, never as an error.
  FORMERLY_RECURRING_IDS: frozenset[str] = frozenset({"alarm.test_monthly"})
  ```
- In `escape_plan/Models/ScoreModels.swift:207-212`:
  ```swift
  /// Items that recurred from S11.34 until the owner made them one-time ticks on 2026-10-05:
  /// the monthly alarm test is ticked once and stays done, never lapses and never lowers the
  /// score. Its cited text still says to test monthly.
  static let formerlyRecurringIDs: Set<String> = ["alarm.test_monthly"]
  ```
- The task copy displayed to the user (`checklist.py:277-280`):
  - Title: *"Test every smoke alarm this month"*
  - Detail: *"Press the test button on every alarm once a month."*
  - Citation: `usfa-smoke-alarms`
**Authoritative Source Checked via Web:**
- U.S. Fire Administration (USFA/FEMA), *Smoke Alarms*: `https://www.usfa.fema.gov/prevention/home-fires/prepare-for-fire/smoke-alarms/` (checked 2026-10-11). USFA unequivocally mandates: *"Test the alarm monthly."*
- NFPA 72 §14.4 (National Fire Alarm and Signaling Code) mandates periodic monthly functional testing.  
**Expected behavior:** Because the item text explicitly instructs the user to test alarms monthly, the application must track recurring monthly maintenance, re-opening every 30 days or highlighting when a monthly test is due.  
**Root cause:** Product decision to prevent the preparedness score from decreasing when users do not re-test monthly ("non-punitive" score policy), implemented by removing recurrence entirely rather than separating display recurrence from score penalties.  
**Impact:** Seriously misleading. A resident testing their alarm in October 2026 will see the item marked "Done" forever. The app will never prompt them to test alarms again, creating a false sense of security that directly undermines USFA/NFPA life-safety guidance.  
**Recommended improvement:** Restore recurrence (`recurrence_days = 30`) for `alarm.test_monthly`. If the product requirement mandates that lapsed tests must not lower the score, set `scoring = False` (identical to `practice.drill_recent` in `checklist.py:322`) rather than making the item non-recurring.  
**Dependencies:** None.  
**Verification status:** Verified by source inspection.  
**Confidence:** High | **Effort:** Small.

---

### A04-02: [HIGH] Redundant Double-Counting of Smoke Alarms on Floors With Sleeping Areas
**Domain:** Fire Safety / Code Compliance & Scoring  
**Location:** `backend/app/scoring/checklist.py:262-275`  
**Observed behavior:** For floors that contain bedrooms, the checklist generator generates both an alarm requirement outside the sleeping area and a second general alarm requirement for the same level.  
**Evidence:**
In `backend/app/scoring/checklist.py:262-275`:
```python
    for floor in home.floors:
        if floor.id in floors_with_bedrooms:
            add(
                f"alarm.sleeping_area.{floor.id}",
                f"Smoke alarm outside the sleeping area on {floor.name}",
                "An alarm goes outside each separate sleeping area — the hallway "
                "serving the bedrooms.",
            )
    for floor in home.floors:
        add(
            f"alarm.level.{floor.id}",
            f"Smoke alarm on {floor.name}",
            "Every level of the home needs at least one smoke alarm.",
        )
```
On a 1-story home with 2 bedrooms (e.g. `demo-homes/bungalow.json`), the generator emits:
1. `alarm.bedroom.room_1` ("Smoke alarm inside Bedroom 1")
2. `alarm.bedroom.room_2` ("Smoke alarm inside Bedroom 2")
3. `alarm.sleeping_area.floor_1` ("Smoke alarm outside the sleeping area on Ground Floor")
4. `alarm.level.floor_1` ("Smoke alarm on Ground Floor")  
**Authoritative Source Checked via Web:**
- NFPA 72 (2022/2025) §29.5.1: Smoke alarms shall be installed (1) in each sleeping room, (2) outside each separate sleeping area, and (3) on each *additional* story of the dwelling unit, including basements.
- USFA Smoke Alarms Guidance: `https://www.usfa.fema.gov/prevention/home-fires/prepare-for-fire/smoke-alarms/` (checked 2026-10-11). An alarm outside the sleeping area provides coverage for that level.  
**Expected behavior:** On floors with sleeping areas, the alarm outside the sleeping area satisfies the level requirement. A separate `alarm.level.{floor.id}` should only be added on levels *without* sleeping areas (e.g. an unfinished basement or living-only floor).  
**Root cause:** Naive loop over all floors without excluding floors already covered by `floors_with_bedrooms`.  
**Impact:** Artificially inflates required alarms. A resident who fully complies with NFPA 72 and USFA standards by placing alarms in bedrooms and the hallway will be penalized 5 points on their preparedness score for failing to install an arbitrary second alarm on the same level.  
**Recommended improvement:** Update the loop to:
```python
    for floor in home.floors:
        if floor.id not in floors_with_bedrooms:
            add(f"alarm.level.{floor.id}", ...)
```  
**Dependencies:** Backend checklist tests (`tests/test_checklist_hazards.py`).  
**Verification status:** Verified by source inspection.  
**Confidence:** High | **Effort:** Small.

---

### A04-03: [HIGH] Total Omission of Carbon Monoxide Safety Across Checklists and Scoring
**Domain:** Life Safety / Checklist & Code Compliance  
**Location:** `escape_plan/Models/Enums.swift:60`, `backend/app/models.py:77`, `backend/app/scoring/checklist.py:1-1307`  
**Observed behavior:** `Equipment.co_detector` is defined in the data model enums, but is completely absent from checklist generation, scoring, and educational advice. The only mention of carbon monoxide in the entire app is an advisory tip on portable generator exhaust after a tornado (`prevention_tips.json:358-364`).  
**Evidence:**
- `grep -rn "co_detector"` reveals occurrences only in `Enums.swift` and `models.py`.
- No items in `checklist.py` check for CO alarms.
- No question in onboarding interview (`OnboardingFlowView.swift`) prompts for CO alarms.  
**Authoritative Source Checked via Web:**
- International Residential Code (IRC 2021/2024) Section R315: Mandates carbon monoxide alarms in dwelling units with fuel-fired appliances or attached garages, placed outside each sleeping area and on each level.
- NFPA 72 / NFPA 720: Standard for the Installation of Carbon Monoxide (CO) Detection and Warning Equipment.
- CPSC (Consumer Product Safety Commission): Recommends CO alarms on each level of the home and outside bedrooms.  
**Expected behavior:** If a home has fuel-fired appliances (e.g. water heater, heating furnace, gas stove) or an attached garage, the checklist should require CO alarms outside sleeping areas and on each level, or at minimum provide an advisory checklist task.  
**Root cause:** Omission during the multi-peril checklist expansion (S6.4/S6.7). Focus was directed at smoke alarms, earthquake mitigation, and tornado safe rooms, leaving the `co_detector` schema field unused.  
**Impact:** Critical blind spot in home life-safety. A resident can achieve a 100/100 readiness score in a home with a gas furnace and water heater while having zero carbon monoxide alarms.  
**Recommended improvement:** Add deterministic CO alarm checklist items when `home.floors` contain gas appliances (`ObjectCategory.water_heater`, gas shutoffs) or garages, and pre-satisfy when `home.household.existing_equipment` contains `co_detector`.  
**Dependencies:** `backend/app/scoring/checklist.py`, `backend/app/models.py`.  
**Verification status:** Verified by source inspection.  
**Confidence:** High | **Effort:** Medium.

---

### A04-04: [MEDIUM] Printable Escape Plan Omits Critical In-Fire Life-Safety Rules
**Domain:** Fire Safety / Export & Narration  
**Location:** `escape_plan/Export/EscapePlanPDF.swift:540-627`  
**Observed behavior:** The printable escape plan PDF (specifically formatted to be posted on a refrigerator or bedroom wall) displays geometric turn-by-turn routes and an outside meeting place, but provides zero life-safety survival instructions.  
**Evidence:**
`EscapePlanPDF.swift` renders:
- Header: Home name, date.
- Outside Meeting Place: Box for meeting location.
- Plan Drawing: 2D geometry with primary and backup routes.
- Legend: Line types (solid/dashed) and glyph markers.
- Summary blocks: Turn-by-turn room descriptions ("Leave the Bedroom through the door...").
There is no text warning the user to feel doors for heat, crawl under smoke, close doors behind them, or get out before calling 911.  
**Authoritative Source Checked via Web:**
- NFPA, *How to make a home fire escape plan*: `https://www.nfpa.org/education-and-research/home-fire-safety/escape-planning` (checked 2026-10-11). NFPA printable plan grids prominently display: *"Feel doors with back of hand before opening"*, *"If smoke is present, crawl low"*, *"Close doors behind you"*, *"Call 911 from outside"*, *"Never go back inside"*.
- American Red Cross, *Home Fire Escape Plan*: `https://www.redcross.org/get-help/how-to-prepare-for-emergencies/types-of-emergencies/fire.html` (checked 2026-10-11).  
**Expected behavior:** The physical artifact taped to a household wall should contain standard life-safety rules so occupants encountering smoke or hot doors know how to react when the primary line is impassable.  
**Root cause:** The PDF generator's summary area was designed exclusively to flow dynamic `NarrationStep` lines without reserving a static footer block for core survival rules.  
**Impact:** A resident following the printed plan may blindly follow the primary route line without checking doors for heat or dropping low under smoke.  
**Recommended improvement:** Dedicate a concise block in the footer or legend area of `EscapePlanPDF.swift` for the 4 cardinal rules:
  1. *Feel door before opening — if warm, use backup route.*
  2. *Smoke rises — crawl low under smoke.*
  3. *Close doors behind you to slow fire.*
  4. *Get out first, then call 911 from outside. Never re-enter.*  
**Dependencies:** `EscapePlanPDF.swift`.  
**Verification status:** Verified by source inspection.  
**Confidence:** High | **Effort:** Small.

---

### A04-05: [MEDIUM] Missing Modern Guidance on Sleeping With Bedroom Doors Closed
**Domain:** Fire Safety / Prevention Tips & Education  
**Location:** `escape_plan/Resources/prevention_tips.json:30-36`, `backend/corpus/prevention_tips.json:30-36`, `backend/corpus/escape-planning-nfpa.md:37`  
**Observed behavior:** All prevention tips and corpus documentation only mention closing doors when evacuating: *"Close doors behind you as you leave. A closed door slows the spread of fire and smoke through the home."* Neither the tips nor the corpus mention sleeping with bedroom doors closed.  
**Evidence:**
- In `prevention_tips.json`:
  ```json
  {
    "id": "fire-close-doors-behind-you",
    "peril": "fire",
    "topic": "during-fire",
    "text": "Close doors behind you as you leave. A closed door slows the spread of fire and smoke through the home.",
    "cite": "usfa-escape-plans",
    "audience": "everyone"
  }
  ```
- No tip or checklist item addresses nighttime closed-door habits.  
**Authoritative Source Checked via Web:**
- UL Firefighter Safety Research Institute (UL FSRI), *Close Before You Doze*: Rigorous thermal and toxic gas testing shows that a closed bedroom door keeps temperatures under 100°F (compared to 1,000°F+ in open areas) and carbon monoxide levels at 100 ppm vs. 10,000 ppm in open rooms.
- NFPA and USFA both incorporate closed bedroom door messaging into residential sleep safety recommendations.  
**Expected behavior:** A comprehensive residential fire prevention and preparedness app should include sleeping with bedroom doors closed as a primary prevention tip.  
**Root cause:** Relying solely on USFA's general escape plan text without including UL FSRI / NFPA modern research on compartmentalization during sleep.  
**Impact:** Missed opportunity to provide one of the single most effective passive fire survival behaviors to families.  
**Recommended improvement:** Add a cited tip to `prevention_tips.json`:
  - Title/Text: *"Sleep with bedroom doors closed. A closed door keeps toxic smoke, heat, and flames out of bedrooms significantly longer during a fire."*  
**Dependencies:** `prevention_tips.json`, `sources.json`.  
**Verification status:** Verified by source inspection.  
**Confidence:** High | **Effort:** Small.

---

### A04-06: [LOW] Stale Orphan Source Exception `usgs-earthquake` in Validation Harness
**Domain:** Corpus Integrity & Maintenance  
**Location:** `backend/corpus/sources.json:94-101`, `backend/corpus/validate.py:51-62`  
**Observed behavior:** `usgs-earthquake` is retained in `sources.json` and exempted from Check 8 in `validate.py` under the justification that `escape_plan/DrillMode/DrillInstructions.swift` still cites it. However, `DrillMode/` was deleted from the app repository on 2026-10-03.  
**Evidence:**
- In `backend/corpus/validate.py:51-62`:
  ```python
  ORPHAN_SOURCE_EXCEPTIONS = {
      "usgs-earthquake": (
          "S11.1 (2026-09-21): usgs.gov/.../prepare is a link directory carrying none of "
          "the claims made of it, so no corpus doc cites it any more. One caller left "
          "(checklist.py was re-pointed by S11.2): the aftershock card in "
          "escape_plan/DrillMode/DrillInstructions.swift, a misattribution... "
          "Owner: S11.10... Then delete both this entry and the source."
      ),
  }
  ```
- File `escape_plan/DrillMode/DrillInstructions.swift` no longer exists anywhere in the repository.  
**Authoritative Source:** Repository filesystem inspection; git log.  
**Expected behavior:** Because no code in `escape_plan` or `backend` references `usgs-earthquake`, the exception should be cleared from `validate.py` and the entry removed from `sources.json`.  
**Root cause:** Dead code cleanup in the iOS app (trimming DrillMode in favor of SceneKit fire simulation) was not back-propagated to the backend corpus validator.  
**Impact:** Minor technical debt; keeps an uncited external URL in the AI grounding table.  
**Recommended improvement:** Delete `usgs-earthquake` from `backend/corpus/sources.json` and remove the exception from `backend/corpus/validate.py`.  
**Dependencies:** `backend/corpus/sources.json`, `backend/corpus/validate.py`.  
**Verification status:** Verified by source inspection.  
**Confidence:** High | **Effort:** Small.

---

### A04-07: [OBSERVATION] Thorough and Ethical Emergency Disclaimers and Scope Partitioning
**Domain:** Product Positioning / Safety Ethics  
**Location:** `ShareWithFireDepartmentCard.swift:59-63`, `ConsentSheet.swift:55-61`, `ResponderSnapshotJSON.swift:81-87`, `ScoreScreen.swift:158-168`, `backend/app/ai/chat/service.py:72-85`  
**Observed behavior:** Across all entry points, the application explicitly warns that it is a pre-disaster educational tool, never an active emergency navigation system, and never a tactical tool for fire departments.  
**Evidence:**
- `ShareWithFireDepartmentCard.swift:59-60`: *"Not for use in an emergency — this is a prevention and readiness snapshot, never a tool for firefighters to use mid-fire."*
- `ConsentSheet.swift:58-60`: *"This is a prevention and readiness snapshot, not a tool for firefighters to use mid-fire. Nothing is ever sent automatically — you pick the app (AirDrop, Messages, Files) each time you share."*
- `ResponderSnapshotJSON.swift:81-87`: Hardcoded static disclaimer strings:
  ```swift
  static let fixedStalenessNote =
      "Home layouts change after remodels. This snapshot is resident-maintained and " +
      "unverified — no department has checked it against the actual home."
  static let fixedTacticalDisclaimer =
      "This is a prevention and readiness snapshot, not a tool for use during an active " +
      "emergency. Responders should not rely on it for tactical decisions."
  ```
- `ScoreScreen.swift:162-164`: *"Fire is measured against code thresholds. Earthquake and severe weather are FEMA/NOAA-grounded guidance."*
- `backend/app/ai/chat/service.py:73-78`: System prompt rule: *"It helps a family prepare BEFORE an emergency — for fire, earthquake and severe weather (tornado). It is not a tool to use during one and it is not a tool for responders: never describe it as helping firefighters navigate a burning house. If someone is in danger right now, rule 4 applies and nothing else matters."*  
**Authoritative Source Checked via Web:** Professional fire service ethics; USFA public education guidelines.  
**Expected behavior:** Complies with highest standards of software safety responsibility.  
**Root cause:** Intentional, high-discipline architectural decisions implemented during S11 development.  
**Impact:** Protects users and emergency responders from misinterpreting the app as an operational emergency tool.  
**Recommended improvement:** Retain these disclaimers intact; do not allow marketing or feature expansion to weaken them.  
**Verification status:** Verified by source inspection.  
**Confidence:** High | **Effort:** None.

---

## 5. Positive Findings

1. **Exact IRC R310 Code Egress Math:** The egress window verification logic (`backend/corpus/egress_thresholds.json` and `backend/corpus/egress-windows-irc.md`) adheres strictly to the 2021 International Residential Code:
   - Area: $\ge 5.7\text{ sq ft}$ ($0.53\text{ m}^2$) for normal openings, $\ge 5.0\text{ sq ft}$ ($0.465\text{ m}^2$) for grade floors.
   - Net clear height: $\ge 24\text{ in}$ ($0.61\text{ m}$).
   - Net clear width: $\ge 20\text{ in}$ ($0.508\text{ m}$).
   - Maximum sill height: $\le 44\text{ in}$ ($1.118\text{ m}$) above floor.
   - Crucially, `egress-windows-irc.md:35` and `egress_thresholds.json:11` explicitly note that a 24" × 20" opening only provides 3.3 sq ft and fails the 5.7 sq ft requirement; area is calculated independently.
2. **NFPA 3-Foot Heating Clearance Rule:** `backend/corpus/object_hazard_thresholds.json` and `backend/app/routing/object_hazards.py:431-467` implement NFPA's 3-foot ($0.9144\text{ m}$) clearance standard for combustible items around heat sources. Furthermore, BUG-01 prevents stove-to-stove false positives.
3. **Rigorous Extinguisher Decision Matrix:** `backend/corpus/escape-planning-nfpa.md:41-58` and `prevention_tips.json:62-76` accurately reproduce USFA's 6-condition decision rule: alert others, 911 called, physically able, small/contained fire, safe from toxic smoke, clear escape route. They explicitly warn that children and older adults should not fight fires.
4. **Vigorous AI Guardrails for Emergency 911 Situations:** `backend/app/ai/chat/service.py:107-109` enforces Rule 4: *"If the user's message suggests an actual, present emergency (smoke, fire, trapped, injury), your FIRST line is always: get out if safe, then call 911."* Furthermore, `claims.py` deterministically checks all model outputs for uncited safety claims and rejects non-compliant replies.
5. **Debunking Dangerous Earthquake Myths:** `backend/corpus/earthquake-preparedness.md:65-81` directly debunks doorways (outdated, not reinforced) and the "Triangle of Life" (misguided idea that does not apply to modern US building construction, as stated by USGS FAQ).
6. **Accurate Gas Shutoff Asymmetry:** The app distinguishes that turning off the main gas valve is a *conditional* decision (only if a leak is suspected by odor, sound, or rapid meter spin), whereas restoring gas is *never* a homeowner task and must be performed exclusively by the utility company.

---

## 6. Systemic Issues and Root Causes

1. **Tension Between Gameified Preparedness Scores and Maintenance Recurrence:**
   - The primary root cause of A04-01 is an architectural tension between maintaining an encouraging score (avoiding score degradation when users fail to check in) and accurately tracking life-safety maintenance intervals.
   - The team treated score deductions and task recurrence as inseparable. When the decision was made that lapsed monthly tests shouldn't penalize the score, the team disabled recurrence rather than decoupling the score weighting from the task lifecycle.
2. **Feature Disconnect Between Schema Definitions and Scoring Rules:**
   - Equipment enums (`co_detector`, `generator`, `extinguisher`) were added to `Enums.swift` and `models.py`, but the checklist generation engine was only partially populated. Fire extinguishers, smoke alarms, and water heaters received rules, while carbon monoxide detection was left unaddressed.
3. **Cross-Repo Asynchrony Between iOS View Refactoring and Backend Corpus Debt:**
   - The retirement of the old iOS practice screen in favor of 3D SceneKit simulations left behind obsolete blocker notes in backend validation files (`validate.py`).

---

## 7. Unverified Assumptions

1. **Fire Department Reception of Responder Snapshots:**
   - The app's design assumes local fire departments will find resident-submitted PDF/JSON floor plans and vulnerable occupant counts useful prior to an incident.
   - *Status:* Inferred but not verified by field trials. Code includes explicit disclaimers that snapshots are unverified by any department and not for tactical use.
2. **Local Municipal Amendments to Model Codes:**
   - The app uses the 2021 International Residential Code (IRC) as a universal baseline. Local municipalities and states frequently adopt older editions (2015, 2018) or enforce local amendments with different sill height or net clear opening tolerances.
   - *Status:* Acknowledged by the app's disclaimer in `egress_thresholds.json:4`: *"The IRC is a model code; adopted editions and local amendments vary by jurisdiction."*

---

## 8. Areas Requiring Further Investigation

1. **Fire Department CAD / Dispatch Interoperability:**
   - Investigation into whether emergency dispatch centers (PSAPs) or Computer-Aided Dispatch (CAD) systems can ingest the `ResponderSnapshotJSON` format, or whether it will remain an exclusively human-read PDF attachment.
2. **Expert Fire Professional Content Review:**
   - While claims match published USFA/NFPA pamphlets, a formal review with a municipal fire prevention bureau should be scheduled to review the wording of route narration instructions, particularly the phrasing for climbing out through secondary egress windows (`RouteNarration.swift:345-348`).

---

## 9. Recommended Priorities

| Priority | Finding ID | Description | Effort | Target File(s) |
|---|---|---|---|---|
| **P1** | A04-01 | Restore monthly recurrence for `alarm.test_monthly`; decouple recurrence from score penalization (`scoring: false`). | Small | `backend/app/scoring/checklist.py`, `escape_plan/Models/ScoreModels.swift` |
| **P1** | A04-02 | Prevent redundant double-counting of smoke alarms on levels already covered by sleeping area hallway alarms. | Small | `backend/app/scoring/checklist.py` |
| **P2** | A04-03 | Implement Carbon Monoxide (CO) alarm checklist items and evaluation rules for homes with fuel-fired appliances or garages. | Medium | `backend/app/scoring/checklist.py` |
| **P2** | A04-04 | Add fundamental emergency fire survival reminders (feel doors, crawl low, close doors, 911 outside) to printable PDF. | Small | `escape_plan/Export/EscapePlanPDF.swift` |
| **P3** | A04-05 | Add cited prevention tip regarding sleeping with bedroom doors closed ("Close Before You Doze"). | Small | `backend/corpus/prevention_tips.json`, `escape_plan/Resources/prevention_tips.json` |
| **P3** | A04-06 | Remove stale orphan source exception `usgs-earthquake` from `sources.json` and `validate.py`. | Small | `backend/corpus/sources.json`, `backend/corpus/validate.py` |
