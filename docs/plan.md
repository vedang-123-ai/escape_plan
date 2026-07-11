Escape Plan (working title) — Full Execution Playbook
Congressional App Challenge 2026 · Deadline: Oct 26, 2026, 12:00 PM ET
This document is designed to be dropped into your repo and executed session-by-session with Claude Code. Each session is a self-contained work order with context, tasks, acceptance criteria, and handoff artifacts. You do not need to finish this in a week or a month — sessions are checkpointed so anyone on the team can pick up any unblocked session at any time.
Team key: P1 = you (backend, ML, agentic AI, hard technical work) · P2 = iOS/frontend teammate (Swift, UI, 3D) · P3 = third teammate (supporting backend, data, product features, testing, video)

PART I — PRODUCT SPECIFICATION (locked decisions)
1.1 What the app is
An iOS app that builds a structured 3D model of the user's home and generates personalized fire escape plans on top of it.
The 3D home engine is the product's core. Users can build their entire home from scratch in a 3D editor — add floors, rooms, doors, windows, and stairs; drag walls, vertices, and joints; connect rooms; label everything. A LiDAR scan (Apple RoomPlan) is an accelerator that pre-populates this model so the user only has to correct and confirm rather than build from zero. This framing matters: the editor is not a fallback for a flaky scan, it is the engine; the scan is a fast on-ramp. Pitch it that way — "raw scans are messy, so we built a real editor" is an engineering story judges respect, and it's honest.
On the completed model, a deterministic routing engine computes a primary and secondary escape route from every room to a safe exterior exit, rendered as animated paths drawn directly on the 3D dollhouse view — including down stairs across floors. This is the money shot of the demo.
An AI layer (Claude API, server-side) does three things, all grounded in a curated corpus of real FEMA / Red Cross / NFPA guidance (never free-form safety advice):
Explains routes and generates recommendations/checklists with citations to the corpus.
Chat assistant — users ask questions ("where should smoke detectors go in a 2-story house?") answered with grounding + awareness of their home model.
Agentic home analysis — an agent walks the home model via tools (inspect rooms, compute routes, check egress dimensions against code thresholds) and proactively surfaces risks: bedrooms with no secondary egress, single-point-of-failure exits, windows too small/high to qualify as egress.
Family profiles (household members: child, elderly, mobility-limited, pets) change both the routes (e.g., avoid stairs-dependent or window egress for a wheelchair user) and the advice. A preparedness score + checklist (explainable, weighted — not a black box) and a practice/drill mode round out the product.
Scope locks: Fire only. iOS only. LiDAR scan only (camera-based photogrammetry and Android are explicitly documented future work — say so in the pitch, don't hide it). No user accounts — local persistence with an anonymous device ID.
1.2 What is explicitly out of scope (write this in the submission)
Furniture/obstruction detection, walkable-area meshing, camera-only capture, Android, multi-user sync, other disaster types. These are deliberate MVP boundaries, not gaps. Judges reward intentional scoping.
1.3 Why this wins (the pitch skeleton)
Civic problem: ~3 in 5 home fire deaths occur in homes without working escape plans/alarms; most families have never drawn an escape plan. Personalized, spatial, practiced plans save lives.
Wow factor (your #1 ranked priority): scan → 3D dollhouse of your actual home → glowing escape routes animating through it, across floors.
Technical originality (your #2): custom 3D editor, deterministic graph routing (yours, not an API call), agentic analysis with real tools. The answer to "isn't this an AI wrapper?" is: the AI never computes routes — our engine does; the AI explains and audits, grounded in cited sources.
Honest demo: show the scan getting you ~80% there fast, then the editor fixing the rest live. Do not stage or hide errors — a judge follow-up question or live demo request should hold up.

PART II — ARCHITECTURE
2.1 System overview
┌─────────────────────  iOS App (SwiftUI)  ─────────────────────┐
│                                                               │
│  Scan Module          3D Engine (SceneKit)      Product UI    │
│  (RoomPlan)  ──────►  • dollhouse render        • plan screen │
│  CapturedStructure    • editor (drag/edit)      • profiles    │
│        │              • route visualization     • checklist   │
│        │                     ▲                  • chat        │
│        ▼                     │                  • drill mode  │
│   local HomeModel JSON  ◄────┴──── single source of truth     │
└───────────────┬───────────────────────────────────────────────┘
                │ HTTPS (JSON)
                ▼
┌────────────────  Backend (Python / FastAPI)  ─────────────────┐
│  /convert   RoomPlan export → HomeModel (the hard mapping)    │
│  /routes    routing engine: graph build + path search         │
│  /analyze   agentic loop (Claude + tools incl. routing)       │
│  /explain   grounded route explanations + recommendations     │
│  /chat      grounded assistant w/ home context                │
│  /score     preparedness score + checklist                    │
│  corpus/    curated FEMA/NFPA/Red Cross excerpts (grounding)  │
│  🔑 Anthropic API key lives HERE, never in the app            │
└───────────────────────────────────────────────────────────────┘

Why a backend at all: you cannot ship an API key inside an iOS binary (trivially extractable). The key lives server-side; the app calls your server. Bonus: the routing engine lives in Python where P1 is strongest, and the same routing code is exposed to the agent as a tool — one implementation, two consumers.
Key decisions and their defaults (each session says "default X; acceptable alternative Y" — Claude Code can deviate if it documents why):
Decision
Default
Acceptable alternative
3D rendering
SceneKit (mature, best-documented for custom geometry + hit-testing/dragging)
RealityKit (more modern; gesture editing is harder to find references for)
Routing location
Backend Python
On-device Swift port later for offline (stretch)
Path search
Dijkstra for primary; secondary = re-run with primary's critical opening(s) penalized/removed (edge-avoidance), or Yen's K-shortest
Any correct, testable equivalent
RAG approach
Corpus is small (~15–25 pages): pass the whole structured corpus in the system prompt with prompt caching; no vector DB needed
Embeddings + cosine retrieval if corpus grows
Agent framework
Hand-rolled tool-use loop with the Anthropic SDK (P1 learns the most, easiest to defend as original work)
A light framework if documented
Backend hosting
Render / Railway / Fly.io free-ish tier
Anything with HTTPS + env-var secrets
Persistence
Local JSON documents on-device (FileManager), schema-versioned
Core Data if P2 prefers

2.2 The HomeModel schema — THE contract of the entire project
Everything reads and writes this one JSON document. The scan converter produces it, the editor mutates it, the routing engine consumes it, the agent inspects it, the renderer draws it. Session S0.2 finalizes it; after that, changes require a version bump and team sign-off. Sketch (S0.2 turns this into a real JSON Schema + pydantic + Swift Codable):
{
  "schema_version": "1.0",
  "home_id": "uuid",
  "name": "Our House",
  "floors": [
    {
      "id": "f1", "level": 0, "name": "Ground Floor", "height_m": 2.7,
      "rooms": [
        {
          "id": "r1", "name": "Living Room", "type": "living",   // enum: bedroom|living|kitchen|hall|bath|garage|other
          "polygon": [[0,0],[5.2,0],[5.2,4.0],[0,4.0]],           // 2D footprint, meters, floor-local coords
          "source": "scan|manual", "confidence": 0.92             // scan-derived items carry confidence
        }
      ],
      "openings": [
        {
          "id": "d1", "kind": "door",                              // door|window
          "room_ids": ["r1","r2"],                                 // 2 rooms = interior; 1 room + "EXTERIOR" = exit
          "wall_segment": {"room_id":"r1","edge_index":2,"t0":0.3,"t1":0.45},
          "width_m": 0.9, "height_m": 2.0, "sill_height_m": 0.0,   // sill matters for window egress
          "egress": {"viable": true, "reasons": []},               // computed: fire-code size/height thresholds
          "source": "scan", "confidence": 0.81
        }
      ]
    }
  ],
  "stairs": [
    {"id":"s1","from":{"floor_id":"f1","room_id":"r3"},"to":{"floor_id":"f2","room_id":"r7"},
     "footprint":[[...]],"kind":"straight|L|U","source":"manual"}
  ],
  "profiles": [
    {"id":"p1","name":"Maya","tags":["child"],"bedroom_room_id":"r7"},
    {"id":"p2","name":"Grandpa","tags":["mobility_limited"],"bedroom_room_id":"r2"}
  ],
  "meta": {"created":"...","modified":"...","address_optional":null}
}

Notes that will save you pain: room footprints are 2D polygons per floor (3D is derived by extrusion — do NOT store meshes); openings reference wall segments parametrically (edge index + t-range) so dragging a wall moves its doors automatically; EXTERIOR is a reserved pseudo-room id; everything scan-derived carries source + confidence so the editor can highlight low-confidence items for review.
2.3 Repo layout (monorepo)
escape-plan/
├── CLAUDE.md                  # project-wide context for Claude Code (S0.1 writes this)
├── docs/
│   ├── playbook/              # THIS document, split: one file per session (S0.1)
│   ├── decisions.md           # running log of deviations from defaults
│   └── tools-used.md          # every library/API/tool — REQUIRED for CAC originality docs
├── schema/
│   ├── homemodel.schema.json
│   └── fixtures/              # synthetic test homes (bungalow, apartment, 2-story)
├── backend/                   # Python 3.11+, FastAPI, pytest; own CLAUDE.md
│   ├── app/ (api/, routing/, convert/, ai/, scoring/)
│   ├── corpus/                # curated guidance, structured markdown + sources.json
│   └── tests/
└── ios/                       # Xcode project, SwiftUI; own CLAUDE.md
    └── EscapePlan/ (Models/, Scan/, Engine3D/, Editor/, Screens/, Networking/)

2.4 How to run a session with Claude Code (the handoff protocol)
S0.1 splits this playbook into docs/playbook/S<x>.md files — one per session, verbatim.
To execute a session, open Claude Code in the repo and say:

 "Read CLAUDE.md, docs/playbook/S1.2.md, and docs/decisions.md. Create a short implementation plan for this session, show it to me, then execute it. Follow the acceptance criteria exactly; when done, update docs/decisions.md with any deviations and docs/tools-used.md with any new dependencies, and write the handoff artifacts listed in the session."



Sessions are sized ~3–6 focused hours each (often less wall-clock with Claude Code, but budget review time — you must be able to explain every line to a judge; CAC requires the work to be yours, so treat Claude Code output like a pair programmer's draft you review, test, and understand, and be upfront in your submission about your development process and tools).
A session is DONE only when all acceptance criteria pass. Never start a session whose prerequisites aren't done.
Parallelism: P1, P2, P3 lanes are designed to run concurrently; the dependency map in Part III shows what blocks what.

PART III — SESSIONS
Dependency map (arrows = "blocks"):
S0.1 ─► S0.2 ─► { S0.3, S1.1 }          S0.4 (independent)
S0.3 ─► S1.3 ─► S2.1 ─► S2.2 ─► S2.3
S0.3 ─► S1.4 ─► S1.5
S1.1 ─► S1.2 ─► { S2.3, S3.1, S3.2, S3.4-routing }
S1.6 needs S1.2 (wraps it)               S3.x need S1.6 + S0.4
S4.1 needs S1.5 + S2.3 + S3.1            S4.2, S4.3, S4.4 after S4.1
S5.x last

Rough calendar at 5–15 combined hrs/week (16 weeks): Phase 0 → by Jul 20 · Phase 1 → by Aug 17 · Phase 2 → by Sep 7 · Phase 3 → by Sep 28 · Phase 4 → by Oct 12 · Phase 5 → Oct 13–24, submit by Oct 24. The immovable milestone: end-to-end demo path working by Oct 5. If you slip, cut S4.2 (drill mode) first, then S3.3 (chat), never the core loop.

PHASE 0 — FOUNDATIONS (Weeks 1–2)
S0.1 — Repo, conventions, and playbook install · Owner: P1 · ~2h · Prereqs: none
Context: Everything downstream assumes this structure exists. Tasks: Create the monorepo per §2.3. Write root CLAUDE.md (project one-paragraph summary, the schema-is-law rule, coding conventions: Python typed + pytest, Swift/SwiftUI, small PRs) and stub CLAUDE.md in backend/ and ios/. Split this playbook into docs/playbook/S*.md. Create empty docs/decisions.md and docs/tools-used.md with table headers (tool | version | what it's used for | license). Set up GitHub with branch protection off (small team, move fast) but PR habit on for anything touching schema/. Acceptance: repo cloned by all 3; each person runs Claude Code in it and it correctly summarizes the project from CLAUDE.md. Handoff: repo URL + 5-line "how we work" note in README.
S0.2 — HomeModel schema v1 + fixtures · Owner: P1 · ~4h · Prereqs: S0.1
Context: The contract (§2.2). Get this right; everything consumes it. Tasks: Turn the §2.2 sketch into (a) schema/homemodel.schema.json (JSON Schema draft 2020-12), (b) backend/app/models.py pydantic models with validation (polygons non-self-intersecting & CCW, openings reference existing rooms/edges, stairs reference existing floors/rooms, ids unique), (c) a validate CLI. Build three fixture homes by hand: bungalow.json (1 floor, 4 rooms, 1 exterior door, 2 egress windows), apartment.json (1 floor, tricky: single exit + hallway bottleneck), twostory.json (2 floors, stairs, bedrooms upstairs). Fixtures are your test bed for the whole project — make them realistic. Acceptance: all fixtures validate; a deliberately broken fixture fails with a clear message; schema doc-comments explain every field. Handoff: schema files + fixtures merged; 10-line schema summary posted to the team.
S0.3 — iOS app scaffold + model layer · Owner: P2 · ~4h · Prereqs: S0.2
Context: The Swift mirror of the schema and the app shell everything plugs into. Tasks: Xcode project (SwiftUI, iOS 17+ target since RoomPlan needs modern devices anyway). Models/ with Codable structs exactly mirroring the schema (write a round-trip test: decode fixture → encode → byte-compare semantically). Tab/navigation shell with placeholder screens: Home(list of saved homes) / Editor / Plan / Assistant / Settings. Load and pretty-print twostory.json fixture on-screen as proof of decode. Basic Networking/APIClient.swift stub pointing at a configurable base URL. Acceptance: app builds and runs on a real device; fixture decodes and displays room names per floor; round-trip test passes. Handoff: screenshot in team chat + note on any schema friction back to P1.
S0.4 — Fire-safety grounding corpus · Owner: P3 · ~4h · Prereqs: none (start day 1)
Context: The AI layer must never invent safety guidance. This corpus is what it cites. It also feeds egress thresholds to the deterministic engine. Tasks: Collect and structure ~15–25 pages of excerpts: NFPA home escape planning (two ways out of every room, meeting point, practice twice a year), egress window requirements (typical IRC values: min opening area ~5.7 sq ft, min height 24in, min width 20in, max sill height 44in — capture the numbers WITH source citations), Red Cross home fire escape plan steps, FEMA/USFA smoke alarm placement. Structure as backend/corpus/*.md with YAML front-matter (source org, doc title, URL, retrieved date, topic tags) + sources.json index. Also produce corpus/egress_thresholds.json — the machine-readable numbers the routing/egress checker will use (S1.1). Note in each file: paraphrase/structure rather than paste long verbatim passages where possible, and keep exact citations. Acceptance: every claim traceable to a named source; thresholds file validates; P1 reviews and signs off that it's sufficient for S3.1. Handoff: corpus merged; 1-page summary of "what guidance we ground on."

PHASE 1 — CORE ENGINES (Weeks 3–6)
S1.1 — Navigation graph builder · Owner: P1 · ~4h · Prereqs: S0.2
Context: HomeModel → graph. Deterministic, fully tested. The routing engine and the agent's tools both sit on this. Tasks: backend/app/routing/graph.py: nodes = rooms + openings + EXTERIOR + stair endpoints; edges: room↔opening (weight = straight-line distance room-centroid→opening midpoint, simple is fine for v1), opening↔opening within a room if you want door-to-door paths, stairs connect their two rooms across floors (weight = stair traversal cost, higher than a normal edge). Compute egress.viable for every window from egress_thresholds.json (S0.4) — window nodes that fail are excluded from the graph (or flagged, kept for "last resort" labeling). Attach an egress annotator that writes results back into the HomeModel. Unit tests on all three fixtures with hand-verified expected graphs. Acceptance: graphs for all fixtures match hand-drawn expectations; non-egress windows correctly excluded; pure functions, no I/O. Handoff: module + a graphviz/matplotlib debug rendering of each fixture's graph committed to docs/.
S1.2 — Routing engine (primary + secondary + bottlenecks) · Owner: P1 · ~5h · Prereqs: S1.1
Context: The deterministic heart. When a judge asks "what if the AI hallucinates a route through a wall" — this is the answer: the AI never touches routing. Tasks: For every room: primary route = Dijkstra to nearest viable exterior exit (doors preferred over windows via edge weights/penalties). Secondary = recompute with the primary route's critical opening(s) removed or heavily penalized; if none exists, return a structured no_secondary_egress finding (this is a FEATURE — it's exactly the risk the agent surfaces). Bottleneck detection: openings whose removal disconnects ≥N rooms from all exits (articulation-point analysis on the graph). Output RoutePlan per profile-less home: per-room primary/secondary as ordered waypoint lists (room-centroid → opening midpoints → … → exterior), each waypoint tagged with floor id so the renderer can draw across floors, plus route metadata (length, uses_stairs, uses_window, exit_id). Profile constraints hook (used by S3.4): a constraints object (avoid_stairs, avoid_windows, max_sill_height) that filters/penalizes edges before search. CLI: python -m app.routing plan fixtures/twostory.json --pretty. Acceptance: correct, hand-verified routes on all fixtures incl. the apartment bottleneck and the two-story stairs; deterministic (same input → same output); ≥15 unit tests; constraints demonstrably change routes on twostory.json. Handoff: CLI demo recording/gif + route JSON samples committed for P2 to render against.
S1.3 — 3D dollhouse renderer · Owner: P2 · ~6h · Prereqs: S0.3
Context: The visual core. Everything the judges remember is on this screen. Tasks: SceneKit view (SwiftUI-wrapped) rendering a HomeModel: rooms = extruded footprint polygons (floor slab + semi-transparent walls, SCNShape from UIBezierPath or custom geometry), openings = cutout markers or inset colored quads on their wall segment (parametric wall-segment refs from the schema make placement deterministic), stairs = simple ramp/step proxy, floors stacked with an "exploded view" slider or per-floor visibility toggle. Orbit/pan/zoom camera. Clean aesthetic: soft neutral palette, room-type accent colors, labels billboarded. Default: SceneKit; alternative RealityKit acceptable if P2 finds it faster — document in decisions.md. Acceptance: all three fixtures render correctly and legibly on-device at 60fps; two-story exploded view works; toggling a floor works. Handoff: 30-sec screen recording of each fixture; this recording is also future demo-video b-roll.
S1.4 — RoomPlan capture module · Owner: P2 · ~4h · Prereqs: S0.3, LiDAR device in hand
Context: The on-ramp. Treat output as draft input to the editor, never final. Tasks: Integrate RoomCaptureView/RoomCaptureSession; support multi-room continuous scan via the merged CapturedStructure API (iOS 17+) — this is the recommended path over per-room stitching; if it proves unstable on your device, fall back to sequential room scans merged by S1.5 and document it. Export raw results as JSON (encode CapturedStructure/CapturedRoom data: walls, doors, windows, openings with transforms + confidence) and stash the USDZ too. Scan UX: instruction screen (lighting, slow pans, doors open), progress state, retry. Acceptance: scan a real 2–3 room space; raw JSON export lands in the app's documents dir with walls/doors/windows present; a second full scan of the same space completes without crashing. Handoff: two raw scan exports (a clean one and a messy one) committed to schema/fixtures/scans/ — S1.5's test inputs.
S1.5 — Scan converter (RoomPlan → HomeModel) · Owner: P1, P3 support · ~6h, expect iteration · Prereqs: S1.4, S0.2
Context: Honestly the hardest single module. RoomPlan gives you wall/door/window bounding boxes with 3D transforms and per-room groupings; you must produce clean 2D room polygons, parametric opening placements, and adjacency. Design for "80% right + flagged uncertainty," not perfection — the editor (Phase 2) is the corrector, by design. Tasks: Backend /convert endpoint + pure module: project walls to 2D per detected room → order into a closed polygon (snap near-collinear walls, close small gaps, rectangularize within tolerance); map each door/window to (room, edge_index, t-range) by nearest wall segment; doors shared between rooms become 2-room openings (adjacency!); doors/windows on unshared exterior walls → EXTERIOR; carry RoomPlan confidence through; anything unresolvable → keep with confidence: low for the editor to highlight, never silently drop. Floor handling: v1 assumes one floor per scan session; multi-floor = scan each floor separately, user adds stairs in the editor (state this in the UX copy). Test against S1.4's real exports AND write 3 synthetic RoomPlan-format fixtures with known ground truth. Acceptance: clean scan converts to a valid HomeModel that renders correctly in S1.3's viewer with ≥1 exterior door and ≥1 window mapped; messy scan converts to a valid (if imperfect) model with low-confidence flags rather than crashing; conversion is idempotent. Handoff: side-by-side screenshot (RoomPlan USDZ vs. rendered HomeModel) + list of known failure modes in decisions.md.
S1.6 — Backend scaffold + deploy · Owner: P3 · ~3h · Prereqs: S1.2 merged (wraps it)
Context: Make P1's engines callable from the phone. Tasks: FastAPI app with /health, /routes (POST HomeModel + optional constraints → RoutePlan), /convert (from S1.5 when ready). Pydantic request/response models reuse models.py. Deploy to Render/Railway/Fly free tier with ANTHROPIC_API_KEY as env var (unused yet, plumb it now); HTTPS; simple bearer token shared with the app so the endpoint isn't fully open. Wire APIClient.swift (with P2) to call /routes with a fixture and log the result. Acceptance: phone on cellular gets routes for twostory.json from the deployed backend in <2s; secrets not in git (checked). Handoff: base URL + token in team password note; curl examples in README.

PHASE 2 — THE 3D EDITOR (Weeks 6–9) — the wow surface
S2.1 — Editor core: rooms, walls, vertices · Owner: P2 · ~6h · Prereqs: S1.3
Context: From viewer to editor. This + S2.3 is what wins the video. Tasks: Selection via SceneKit hit-testing (tap room/wall/vertex; selected = highlight + handles). Gestures: drag a vertex (moves point, connected walls follow), drag a wall edge (translates it, neighbors stretch), drag a room (whole-polygon translate). Snapping: to grid (e.g., 10cm), to axis-alignment, to adjacent room walls (this is how users "connect" rooms cleanly). Add room (default rectangle placed on current floor), delete room, rename, set room type. Floor management: add floor above/below, switch active floor, per-floor edit isolation. Every mutation goes through a single HomeModelStore (reducer-style) so undo/redo (S2.2) and persistence are trivial — parametric opening refs mean doors ride along automatically when walls move (schema design paying off). Acceptance: starting from an empty model, build the bungalow fixture's shape by hand on-device in <5 minutes; drags feel smooth; no gesture puts the model in an invalid state (validate on mutation, reject with haptic). Handoff: screen recording "building a home from scratch in 4 minutes" — literal demo-video b-roll.
S2.2 — Editor: openings, stairs, undo · Owner: P2 · ~5h · Prereqs: S2.1
Tasks: Add door/window: tap a wall → placement mode → slide along the wall (t-parameter) → set width/height (+ sill height for windows) with sensible defaults (door 0.9×2.0m, window 1.0×1.2m sill 0.9m); doors on shared walls auto-detect the second room (adjacency for the graph). Add stairs: pick room on floor N, pick room on floor N+1, choose footprint corner — renders the ramp proxy and writes the stairs entry. Low-confidence scan items rendered with a distinct "needs review" treatment (pulsing outline); tapping one offers confirm / adjust / delete. Undo/redo stack on HomeModelStore. Autosave to local document on every mutation batch. Acceptance: on a converted real scan, fix a misplaced door and confirm all flagged items in <2 min; add working stairs between floors of a hand-built 2-story; undo/redo across 20 mixed operations is consistent. Handoff: updated recording; note any schema pressure to P1.
S2.3 — Route visualization on the 3D model · Owner: P2 · ~5h · Prereqs: S1.3 + S1.2 (route JSON), S1.6 (live endpoint)
Context: The money shot: animated escape paths flowing through the dollhouse, down the stairs, out the door. Tasks: Fetch RoutePlan from /routes for the current model. Render per-room routes as smooth polylines slightly above floor level (Catmull-Rom through waypoints; tube/ribbon geometry), primary = bold warm color with an animated directional pulse (shader modifier or animated texture offset), secondary = cooler dashed style. Route follows waypoints across floors via the stair nodes (camera can follow it in "tour" mode — one button that flies the camera along the primary route; this is a demo-video weapon). Room picker UI: select a room (or "everyone") → show its routes; exit markers glow. Empty/failure states: no_secondary_egress renders as a visible warning badge on that room, not an error. Acceptance: on twostory.json, select an upstairs bedroom → primary route animates down the stairs and out the front door, secondary shows the egress window path; tour mode runs smoothly; warning badge shows on a fixture room designed to lack secondary egress. Handoff: the recording. Everyone will know it when they see it.
S2.4 — Persistence & documents · Owner: P3 · ~3h · Prereqs: S2.1
Tasks: Local home documents: save/load/list/delete HomeModel JSONs in app documents dir with schema-version field and a migration stub; "duplicate home" (handy for testing); export/share raw JSON (debugging + power-user cred). Home list screen (with P2) showing name/floors/rooms/last-modified. Acceptance: kill and relaunch app → everything persists; two saved homes coexist; export produces a file that validates against the schema. Handoff: merged; test checklist appended to decisions.md.

PHASE 3 — THE AI LAYER (Weeks 9–12)
S3.1 — Grounded explanations + recommendations service · Owner: P1 · ~5h · Prereqs: S1.2, S1.6, S0.4
Context: First Claude integration. Iron rule: the model explains and recommends only from the corpus and the computed RoutePlan; it never invents guidance and never computes routes. Tasks: backend/app/ai/grounded.py: system prompt = role + hard grounding rules + the full structured corpus (it's small — use prompt caching on the corpus block to keep cost/latency down; log cache hits). /explain endpoint: input = HomeModel + RoutePlan (+ optional profile), output = structured JSON (schema-enforced via tool-use/structured output): per-room route explanation in plain family-friendly language, top-N recommendations each with {claim, action, source_citation} where citation must reference a corpus doc id — validate citations against sources.json server-side; reject/retry uncited safety claims. Temperature low. Golden tests: 5 fixture+route inputs with snapshot outputs reviewed by hand; a red-team test proving an uncorpused question ("should I jump from the second floor?") gets a safe deferral, not invented advice. Acceptance: valid, cited JSON on all fixtures; citation validator demonstrably rejects a fabricated source in tests; p95 latency <6s with caching. Handoff: endpoint live; 3 sample outputs pasted for team review; prompt files committed (they're part of your original work story).
S3.2 — Agentic home analysis · Owner: P1 · ~6h · Prereqs: S3.1
Context: Your showcase module — the "AI safety inspector" that walks the home. Hand-roll the loop; it's more defensible as original work and you'll understand every step. Tasks: Tool-use loop (Anthropic SDK, while stop_reason == "tool_use"): tools = get_home_summary(), get_room(id), list_openings(floor_id), compute_routes(constraints?) (calls YOUR S1.2 engine), check_egress(opening_id) (S1.1 thresholds), search_corpus(topic). Agent contract (system prompt): inspect systematically → produce findings list, each {severity: high|med|low, room_ids, finding, evidence: [tool_call_refs], recommendation, citation} — evidence must reference actual tool results (the loop records a trace; validate finding→evidence linkage server-side). Cap iterations (~15) and tokens; graceful partial results on cap. /analyze endpoint returns findings + the tool trace (the trace itself is demo/pitch gold: "here's the agent literally checking each bedroom"). Seed the fixtures with plantable issues (bedroom with only a too-small window; single-exit apartment) and assert the agent finds them. Acceptance: on apartment.json the agent flags the single-point-of-failure exit with correct evidence; on twostory.json it flags any bedroom lacking secondary egress; zero findings without evidence links; runs <60s. Handoff: endpoint + a rendered example trace in docs/ (also feeds the pitch's "technical depth" section).
S3.3 — Chat assistant (backend + UI) · Owner: P3 backend, P2 UI · ~4h · Prereqs: S3.1
Tasks: /chat: multi-turn, system prompt = grounding rules + corpus (cached) + a compact serialized summary of the user's HomeModel + latest RoutePlan + profiles, so answers are house-aware ("your kids' bedroom is upstairs — per NFPA, practice the window route with an adult"). History sent from client each turn (stateless server). Safety behaviors in-prompt: emergencies → "call 911 first"; uncorpused topics → honest deferral. iOS chat screen: minimal, streaming if easy, otherwise typing indicator. Acceptance: asks about smoke detectors → cited, house-specific answer; asks something outside corpus → graceful deferral; conversation survives app background/foreground. Handoff: merged + 5 screenshot Q&As for the submission materials.
S3.4 — Family profiles end-to-end · Owner: P3 (UI with P2, routing hook with P1) · ~4h · Prereqs: S1.2's constraints hook, S2.3
Context: The "personalized, not generic" proof — a profile change must visibly change the 3D routes live. This is a scripted demo-video moment. Tasks: Profile CRUD UI (name, tags: child/elderly/mobility_limited/pet, assigned bedroom). Tag→constraints mapping (documented, deterministic): mobility_limited → avoid_stairs + avoid_windows (may yield no_viable_route finding → surfaces as a high-severity flag, which is honest and powerful); child → child's route defaults to accompanied-adult pairing in explanation + window-egress deprioritized. Plan screen gains a profile selector; switching re-fetches /routes with constraints and the 3D paths visibly change. Profiles also flow into /explain, /analyze, /chat context. Acceptance: on twostory.json, switching Grandpa(mobility_limited) vs Maya(child) changes the rendered route or raises the no-viable-route flag; explanation text reflects the profile; all deterministic mappings documented. Handoff: recording of the live switch — straight into the demo script.
S3.5 — Preparedness score + checklist · Owner: P3 · ~3h · Prereqs: S3.1, S3.2
Tasks: Explainable score (0–100), documented weights — e.g., every room has primary route (30), % rooms with secondary (25), no high-severity agent findings (20), smoke-alarm checklist items confirmed (15), plan practiced/meeting point set (10). NOT a black box; the breakdown renders as a tappable list. Checklist = deterministic items (from thresholds + findings) + grounded recommendations (from S3.1), each with done-state persisted on the home document. Score updates live as items complete (nice score-count-up animation with P2). Acceptance: score reproducible from documented weights by hand-calculation; completing an item updates score; breakdown screen legible. Handoff: weights documented in docs/ (judges may ask exactly this).

PHASE 4 — INTEGRATION & PRODUCT (Weeks 12–14)
S4.1 — The golden path, end-to-end · Owner: P2 lead, all hands · ~5h · Prereqs: S1.5, S2.3, S3.1
Context: Wire the loop the demo will follow: Scan → Convert → Editor review/fix → Routes on 3D → Analysis + score → Profile switch. Tasks: Onboarding flow stitching modules: post-scan auto-convert with progress UI → land in editor with "N items need review" → confirm → plan screen auto-fetches routes + kicks off /analyze in background → findings and score appear. Kill every dead-end: loading, empty, offline, and failure states for each backend call (cached last-good RoutePlan if offline). App name + icon decision (S4.4 polishes). Acceptance: one person, one real home, full loop start-to-finish without touching Xcode; every failure injected (kill backend mid-flow) degrades gracefully. Handoff: full-loop screen recording — the demo video skeleton.
S4.2 — Drill / practice mode · Owner: P3 (+P2 UI) · ~4h · Prereqs: S4.1 · FIRST CUT IF BEHIND
Tasks: Pick ONE format and keep it small. Recommended: guided walkthrough — select family member → app steps through their primary route waypoint-by-waypoint on the 3D view (camera tour from S2.3 reused!) with instruction cards ("check the door with the back of your hand — NFPA") → ends at meeting point card → "mark plan as practiced" (feeds score). Quiz variant acceptable if simpler. Acceptance: complete a drill for two different profiles; practiced-state persists and moves the score.
S4.3 — Real-home testing + bug bash · All hands · ~4h · Prereqs: S4.1
Tasks: Scan ≥3 real, different homes (incl. at least one none of you lives in — a relative's). For each: full golden path, log every failure in a shared sheet (severity, module, repro). Fix top items; anything unfixable becomes either a graceful state or an honest "known limitation" line in the submission. Verify the editor can fully recover the worst scan. Acceptance: golden path succeeds on 3/3 homes (editor-assisted is fine — that's the product story); zero crashes on the demo path.
S4.4 — Polish pass · Owner: P2 · ~4h · Prereqs: S4.3
Tasks: Visual pass on the two screens the video lingers on (3D plan screen, editor): lighting/materials on the dollhouse, micro-animations, haptics on editor snaps, app icon, launch screen, consistent type/color. Copy pass everywhere (P3): plain, warm, family-facing. Acceptance: side-by-side before/after; team unanimously prefers after.

PHASE 5 — DEMO VIDEO & SUBMISSION (Weeks 14–16)
S5.1 — Script + storyboard · Owner: P3 lead, P1 tech-accuracy pass · ~3h · Prereqs: S4.1 done
Beats (~3 min): (1) hook: the 2-minutes-to-escape statistic + "most families have no plan" (cited); (2) scan a real home — honest: "the scan gets us ~80% there in minutes"; (3) editor: fix flagged items on camera, add stairs — "so we built a full 3D home editor"; (4) money shot: routes animating through the dollhouse, camera tour down the stairs; (5) agent findings appearing ("our AI inspector found the kids' room has no second way out") + profile switch visibly changing routes; (6) score/checklist/drill fast montage; (7) what we learned + what's next (Android/camera capture, more disasters) + team roles ("we wrote the routing engine; AI explains, never routes"). Storyboard maps each beat to existing session recordings — you've been collecting b-roll all along. Acceptance: table-read under 3:15; every claim in the script is true of the shipped build.
S5.2 — Film + edit · All hands · ~6h across days · Prereqs: S5.1
Tasks: Screen-record on-device (4K screen capture via QuickTime/ReplayKit), a few real-world shots of the scan being performed, voiceover per script, captions (judges often watch muted). Two full edit passes with a day between. Export per CAC video specs; upload unlisted YouTube. Acceptance: three non-team viewers understand what the app does and can name the wow moment unprompted.
S5.3 — Submission package + submit early · Owner: P1 accountable, all contribute · ~3h · Deadline: submit by Oct 24
Tasks: Complete docs/tools-used.md → the CAC-required documentation of every library/framework/API (RoomPlan, SceneKit, FastAPI, Anthropic SDK, pydantic, hosting, and your AI-assisted development process — CAC's originality rule requires documenting external tools and being able to demonstrate your own technical understanding, so disclose how you used Claude Code and be ready to explain any part of the code). Write the app description + "what we learned" answers (draft from decisions.md — you've been journaling this all project). Verify district registration details, all teammates listed, video link works logged-out. Submit; screenshot confirmation. Acceptance: submitted ≥48h before deadline; confirmation saved in repo.

PART IV — OPERATING NOTES
Weekly rhythm (fits 5–15 combined hrs/wk)
One 30-min sync (statuses = session IDs: "S1.2 done, starting S1.6"), then async. Each person runs 1–2 sessions/week max. Checkpoint dates: Aug 17 (Phase 1 done?), Sep 7 (editor + routes rendering?), Oct 5 (golden path?). Miss a checkpoint → cut from the bottom of the cut-order below, never compress testing or the video.
Cut order if behind (first cut → last cut)
S4.2 drill mode → S3.3 chat → S3.5 score (keep checklist) → camera tour mode → S3.2 agent becomes "top-3 findings" simplified. Never cut: scan→editor→3D routes→profile switch. That loop IS the app.
Risk register
Risk
Mitigation
Multi-room continuous scan flaky on your device
S1.4 has the per-room fallback path; the editor absorbs scan imperfection by design
S1.5 converter rabbit-hole
Timebox to 2 sessions; "80% + flagged low-confidence" is the spec, not a compromise
SceneKit gesture editing harder than expected
Reduce v1 to wall-drags + room-drags only (skip per-vertex); still demos great
Backend cold-starts on free hosting
Warm-up ping before demo recording; or bump to paid tier for October
API costs
Prompt caching + capped agent iterations; expect small-dollar totals at your usage
Hours crunch when school starts (Sept)
Phases 0–2 are deliberately front-loaded into summer — protect July/August throughput
Only one LiDAR device
Converter tests run on committed scan exports, so P1/P3 never need the device

The one rule
Every session ends with: acceptance criteria verified, decisions.md updated, tools-used.md updated, handoff artifact posted. A session without a handoff didn't happen.
