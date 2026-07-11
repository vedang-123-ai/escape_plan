---
description: Grounding-corpus authoring and citation conventions
globs: ["backend/corpus/**"]
alwaysApply: false
---

# Corpus rules (backend/corpus/)

The corpus is the ONLY source the AI layer may cite. Established in S0.4 (see docs/decisions.md):

- Every content file is markdown with YAML front-matter: source org, doc title, URL, retrieved
  date, topic tags. Every claim carries an inline `[cite: source-id]` tag; ids must resolve in
  `sources.json`.
- Compilation docs (`fire-facts-stats.md`, `special-considerations.md`) have non-source primary
  ids and only ever cite underlying external sources.
- Paraphrase and structure rather than paste long verbatim passages; keep exact citations.
- `egress_thresholds.json` carries both imperial (as codified, for citation fidelity) and
  metric values; **metric is authoritative for computation** (HomeModel is in meters).
- After ANY corpus change, run `python3 backend/corpus/validate.py` — it checks source
  resolution, front-matter, cite tags, and imperial↔metric consistency (1% tolerance).
- Never add safety guidance without a real, named source. No source → it doesn't go in.
