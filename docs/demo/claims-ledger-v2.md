# Truth ledger — v2

| # | Claim (as spoken) | Status | Evidence |
|---|---|---|---|
| 1 | "as little as two minutes to get out" | VERIFIED | `[cite: redcross-two-minutes]` → `backend/corpus/sources.json` |
| 2 | "about a quarter of families have made and practiced an escape plan" | VERIFIED | `[cite: redcross-escape-fact-sheet]` → `sources.json` |
| 3 | "scan your home, and it builds a 3D model" | VERIFIED | `Scan New Home` feature, `backend/app/convert/` |
| 4 | "gets us most of the way there... never perfect" | VERIFIED | Schema `source`+`confidence` invariant; flagged-not-dropped |
| 5 | "full 3D editor... fix any mistakes" | VERIFIED | `HouseScreen` 3D house view + editor features |
| 6 | "primary escape route, and a secondary route through a different exit" | VERIFIED | Routing engine; NFPA two-ways-out logic |
| 7 | "deterministic engine we wrote" | VERIFIED | `backend/app/routing/` |
| 8 | "fire drill simulation... watch everyone reroute" | VERIFIED | House fire simulation + "Who does what" cards |
| 9 | "flags object hazards, warning you if furniture narrows a path" | VERIFIED | Object-hazard engine, `Route check issues` in inventory |
| 10 | "working firefighter... thought the idea was really cool... pointed us toward prevention" | VERIFIED | `docs/playbook/01-product-spec.md` Section 2 |
| 11 | "readiness score and a checklist for fire, earthquakes, and tornadoes" | VERIFIED | Score screen, `ScoreModels.swift` |
| 12 | "fire module is fully quantified... earthquake and tornado modules use FEMA and NOAA readiness guidance" | VERIFIED | Scope lock (`CLAUDE.md`, spec) |
| 13 | "share a snapshot of your plan with your local fire department" | VERIFIED | `ShareWithFireDepartmentCard` |
| 14 | "AI assistant to chat about your home" | VERIFIED (Needs credits) | `AssistantScreen`, `/chat` (cannot film without funded backend) |
| 15 | "Every safety answer is grounded... cites its source... if it can't back something up, it says so" | VERIFIED in tests (stub client); live behaviour needs credits (S11.49) | S11.44: uncited safety replies are retried, then replaced by a deferral; small talk and the 911 line are legitimately uncited, so "every answer" was too strong. `backend/tests/test_chat.py` |
| 16 | "AI explains, but it never computes a route" | VERIFIED | Routing = Python engine, AI layer explains only |
