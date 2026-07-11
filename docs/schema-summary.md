# HomeModel v1.0 — 10-line team summary (S0.2 handoff)

1. One JSON document per home: `schema_version ("1.0"), home_id, name, floors[], stairs[], profiles[], meta`. Contract lives at `schema/homemodel.schema.json`; changes now require a version bump + sign-off.
2. A floor = `id, level (unique int), name, height_m, rooms[], openings[]`; all coordinates are meters in a floor-local 2D frame.
3. A room = `id, name, type (bedroom|living|kitchen|hall|bath|garage|other), polygon` — CCW, non-self-intersecting, first vertex not repeated; 3D is extruded from `height_m`.
4. Edge convention: edge *i* runs vertex *i* → vertex *(i+1) mod n*. Openings sit on walls parametrically: `wall_segment {room_id, edge_index, t0, t1}` — drag a wall and its doors ride along.
5. An opening = door|window with `room_ids` (always exactly 2): two rooms = interior adjacency; room + `EXTERIOR` (reserved pseudo-room) = an exit. `width_m/height_m/sill_height_m` are authoritative for egress checks.
6. `egress {viable, reasons[]}` is computed-only (S1.1 annotator, IRC thresholds from the corpus) — never hand-authored, never AI-authored.
7. Stairs connect `from {floor_id, room_id}` → `to` on a *different* floor (JSON key is `from`; pydantic field is `from_`, Swift should use CodingKeys).
8. Provenance: everything carries `source: scan|manual`; scan items MUST carry `confidence` (low values get "needs review" treatment in the editor, never silently dropped).
9. Ids are globally unique across ALL entity kinds (floors, rooms, openings, stairs, profiles); `additionalProperties: false` everywhere — unknown fields fail validation.
10. Validate with `cd backend && python3 -m app.validate ../schema/fixtures/*.json` (runs JSON Schema + pydantic). Fixtures: `bungalow` (clean), `apartment` (planted: single exit, all windows non-viable), `twostory` (planted: kids' window too small; profiles Maya/Grandpa) + `fixtures/invalid/` for failure cases.
