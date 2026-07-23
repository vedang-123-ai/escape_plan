# PART II — ARCHITECTURE

PART II — ARCHITECTURE
2.1 System overview
┌───────────────────── iOS App (SwiftUI) ─────────────────────┐
│ │
│ Scan Module 3D Engine (SceneKit) Product UI │
│ (RoomPlan) ──────► • dollhouse render • plan screen │
│ CapturedStructure • editor (drag/edit) • profiles │
│ │ • route visualization • checklist │
│ │ ▲ • chat │
│ ▼ │ • drill mode │
│ local HomeModel JSON ◄────┴──── single source of truth │
└───────────────┬───────────────────────────────────────────────┘
 │ HTTPS (JSON)
 ▼
┌──────────────── Backend (Python / FastAPI) ─────────────────┐
│ /convert RoomPlan export → HomeModel (the hard mapping) │
│ /routes routing engine: graph build + path search │
│ /analyze agentic loop (Claude + tools incl. routing) │
│ /explain grounded route explanations + recommendations │
│ /chat grounded assistant w/ home context │
│ /score preparedness score + checklist │
│ corpus/ curated FEMA/NFPA/Red Cross excerpts (grounding) │
│ 🔑 Anthropic API key lives HERE, never in the app │
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
Hand-rolled tool-use loop with the Anthropic SDK
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
 "id": "r1", "name": "Living Room", "type": "living", // enum: bedroom|living|kitchen|hall|bath|garage|other
 "polygon": [[0,0],[5.2,0],[5.2,4.0],[0,4.0]], // 2D footprint, meters, floor-local coords
 "source": "scan|manual", "confidence": 0.92 // scan-derived items carry confidence
 }
 ],
 "openings": [
 {
 "id": "d1", "kind": "door", // door|window
 "room_ids": ["r1","r2"], // 2 rooms = interior; 1 room + "EXTERIOR" = exit
 "wall_segment": {"room_id":"r1","edge_index":2,"t0":0.3,"t1":0.45},
 "width_m": 0.9, "height_m": 2.0, "sill_height_m": 0.0, // sill matters for window egress
 "egress": {"viable": true, "reasons": []}, // computed: fire-code size/height thresholds
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
├── CLAUDE.md # project-wide context for Claude Code (S0.1 writes this)
├── docs/
│ ├── playbook/ # THIS document, split: one file per session (S0.1)
│ ├── decisions.md # running log of deviations from defaults
│ └── tools-used.md # every library/API/tool — REQUIRED for CAC originality docs
├── schema/
│ ├── homemodel.schema.json
│ └── fixtures/ # synthetic test homes (bungalow, apartment, 2-story)
├── backend/ # Python 3.11+, FastAPI, pytest; own CLAUDE.md
│ ├── app/ (api/, routing/, convert/, ai/, scoring/)
│ ├── corpus/ # curated guidance, structured markdown + sources.json
│ └── tests/
└── ios/ # Xcode project, SwiftUI; own CLAUDE.md
 └── EscapePlan/ (Models/, Scan/, Engine3D/, Editor/, Screens/, Networking/)

2.4 How to run a session with Claude Code (the handoff protocol)
S0.1 splits this playbook into docs/playbook/S<x>.md files — one per session, verbatim.
To execute a session, open Claude Code in the repo and say:

 "Read CLAUDE.md, docs/playbook/S1.2.md, and docs/decisions.md. Create a short implementation plan for this session, show it to me, then execute it. Follow the acceptance criteria exactly; when done, update docs/decisions.md with any deviations and docs/tools-used.md with any new dependencies, and write the handoff artifacts listed in the session."



Sessions are sized ~3–6 focused hours each (often less wall-clock with Claude Code, but budget review time — you must be able to explain every line to a judge; CAC requires the work to be yours, so treat Claude Code output like a pair programmer's draft you review, test, and understand, and be upfront in your submission about your development process and tools).
A session is DONE only when all acceptance criteria pass. Never start a session whose prerequisites aren't done.
Parallelism: P1, P2, P3 lanes are designed to run concurrently; the dependency map in Part III shows what blocks what.
