# PART I — PRODUCT SPECIFICATION (locked decisions)

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
