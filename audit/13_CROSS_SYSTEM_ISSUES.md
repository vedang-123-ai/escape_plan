# 13 · Cross-System Issues

Canonical home for AUD-025, AUD-030. Also the trace map of every major flow end to end, with the break points
cross-referenced to their canonical findings.

## End-to-end traces

### T1. Score (Home tab)
`HomeScreen` → `ReadinessStore.load` → `HomeDocumentStore.load` (migrates) → `APIClient.score` (POST `/score`,
`{home, checklist_state: [String: Bool]}`, 90 s) → `main.score` (`ScoreRequest.checklist_state: dict[str, bool]`) →
3 × `compute_route_plan` → `compute_score(..., now=None)` → `ScoreBreakdown` → iOS decode → `breakdown` + `ScoreCache`.
**Breaks:** response not tied to the home it was asked for (AUD-014); recurrence needs `now` + ISO strings, gets neither
(AUD-026); AI drafts scored (AUD-023); unbounded input (AUD-004).

### T2. Routes (House / Drill)
`HouseScreen.fetchRoutes` / `DrillScreen.beginDrill` → `fetchRoutesCached(home, peril?, profileID?)` → `/routes` →
`RoutePlan` → `RoutePlanCache.save` (key: `home_id` only) → overlay.
**Breaks:** cache ignores peril/profile/model version (AUD-028); drill appends client-authored guidance to an engine
finding (AUD-025); profiles unreachable (AUD-020).

### T3. Chat
`AssistantScreen.send` → full history + active home → `/chat` (60 s) → `chat()` → Anthropic → citation-id check →
reply.
**Breaks:** 60 s < measured cold start + model time (AUD-032); uncited claims accepted (AUD-030); unbounded history
(AUD-033/035); credits out (AUD-002).

### T4. Build from text/photo/PDF
`BuildFromPlanView` → `/build {description?, image_b64?, image_media_type: "image/png"}` (180 s) → 40-iteration tool
loop → `BuildResult.home` → saved → **made active and scored**.
**Breaks:** photo bytes mislabelled (AUD-024); no review gate (AUD-023); server keeps looping after client timeout
(AUD-035).

### T5. Scan → home
`ScanFlowView` → `Documents/Scans/<stamp>/raw.roomplan.json` → `/convert` → `HomeModel` → saved → active →
`router.openHouse`. **Breaks:** raw scan files never cleaned (AUD-008); `/convert` hides server bugs as 422 (AUD-010).

### T6. Re-check a room
Task "rescan.home" → room picker → scan → `/convert` → `/diff_obstructions {stored_model, scan_model, target_room_id}`
→ `DiffReviewSheet` → append object → `try? save`. **Breaks:** AUD-017, AUD-013, AUD-029.

### T7. Sync
`RootView.task`/foreground/sign-in → `SyncManager.sync` → `GET /homes` → `SyncReconciler.plan` (pure) → per action
`POST /homes` / write pulled / `DELETE /homes/{id}`. **Breaks:** AUD-015, AUD-016, AUD-018, AUD-031, AUD-013.

### T8. Share with fire department
Tasks card (active home ✅) / Settings (most-recently-modified home ❌) → consent → `EscapePlanExporter` → PDF + JSON →
share sheet. **Breaks:** AUD-027.

## Contract mismatches found

| Client sends / expects | Server accepts / returns | Finding |
|---|---|---|
| `checklist_state: [String: Bool]` | recurrence logic wants `str` ISO timestamps and a `now` | AUD-026 |
| `image_media_type: "image/png"` for any photo | forwards the label to Anthropic unchecked | AUD-024 |
| Chat timeout 60 s | cold start alone measured 51 s | AUD-032 |
| `ScoreBreakdown` (no home id) | — | AUD-014 |
| `POST /homes` with `home_id` (no base revision) | server increments blindly | AUD-016 |
| Offline cache keyed by `home_id` | plans differ by peril and profile | AUD-028 |

No field-name or type drift was found in the HomeModel contract itself: the schema enum, pydantic `Literal["2.1"]` and
Swift `SchemaMigrator.currentVersion = "2.1"` agree, and all 7 bundled fixtures are byte-identical to `schema/fixtures/`.

---

### [AUD-025] The drill appends client-written, unconditional tornado guidance that contradicts the engine's conditional finding

**Severity:** P1
**Location:**
- `escape_plan/DrillMode/DrillScreen.swift:828-832`:
  `routesNotice = "\(finding.detail) Leave immediately and seek shelter in a nearby sturdy building. [cite: redcross-tornado]"`
- Engine text it is appended to: `backend/app/routing/engine.py:365-377` — "No interior room could be reached from
  here. **If you are in a mobile or manufactured home**, go now to a nearby sturdy building or community shelter."
- Corpus: `backend/corpus/severe-weather-tornado.md:18-24` (shelter ranking: safe room, then basement / interior room)
- Test coverage that misses it: `escape_planTests/DrillModeTests.swift:101-119` validates cite ids only in
  `DrillInstructions`, not in `DrillScreen`

**Category:** cross-system / grounding (core product rule)
**What I found:** The app authors its own safety instruction in Swift, makes it unconditional, and tags it with a
citation that resolves (so it looks grounded). The engine's own sentence limits "go to a sturdy building" to mobile and
manufactured homes.
**Current behavior:** In a tornado drill for a site-built house where the engine could not reach an interior room (for
example, an incomplete scan with no interior rooms marked), the user is told to "Leave immediately" — the opposite of
NWS/Red Cross guidance for a house (lowest floor, interior room). The raw `[cite: …]` tag is shown as text.
**Expected behavior:** The app shows the engine's finding verbatim (the comment two lines below says exactly this:
"Findings are the engine's words, shown verbatim — the app never writes its own safety judgments").
**Why this matters:** "The AI never invents safety guidance" is the project's central claim; here the *client* invents
it, and the wording could lead someone to leave shelter.
**Evidence:** Code reading of both sides; `grep -rn "nearby sturdy building" backend escape_plan`.
**Affected systems:** Drill (tornado peril), pitch truth, grounding audits.
**Potential fix direction:** Delete the appended sentence; render `finding.detail` (and `finding.citation`) as the
engine sends them. Add a test that every `routesNotice` string is either engine text or from `DrillInstructions`.
**Dependencies / considerations:** Run `grounding-auditor` after the fix.

---

### [AUD-030] Chat accepts replies that make safety claims with no citation

**Severity:** P2
**Location:** `backend/app/ai/chat/service.py:142-146` (`find_invalid_chat_citations` returns only ids *not in*
`sources.json`), `:199-225` (retry loop); rule text in `.claude/rules/vendors/anthropic.md` ("validate … and reject/retry
uncited claims") and `docs/decisions.md` 2026-07-13 (S3.1: "uncited/fabricated citations rejected server-side")
**Category:** cross-system / grounding
**What I found:** `/explain` enforces a citation per recommendation through its structured schema. `/chat` is free text
and only rejects *fabricated* ids; a reply with zero citations passes.
**Current behavior:** The model's instruction to cite is the only control. `ChatResponse.citations` may be empty and
iOS says so is legitimate ("small talk and 911 deferrals").
**Expected behavior:** Either a structured chat output (claims[] each with a citation, plus free "small talk"), or a
server heuristic that flags imperative/safety sentences without a cite tag and retries — or document chat as a
weaker-grounded surface and say so in the UI.
**Why this matters:** The chat is the one AI surface a judge will actually type into.
**Evidence:** Code reading; the eval suite (`backend/tests/evals/`) grades cases but the production path has no
uncited-claim check.
**Affected systems:** Assistant, pitch claims about grounding.
**Potential fix direction:** Reuse the eval graders' claim detection in the service as a post-check, or move chat to
tool-use structured output like `/explain`.
**Dependencies / considerations:** More retries = more cost (AUD-035). Needs live-model evaluation once credits exist.
