# S3.4 — Family profiles (backend/deterministic half)

- **Who:** P3 (Claude Code, `../ep-s34` worktree, branch `s34-profiles`)
- **Date(s):** 2026-07-16
- **Status when I stopped:** Backend half done and acceptance-verified (120 passed). iOS profile
  CRUD UI + live 3D re-fetch NOT started — out of scope for this lane, see Next steps.

## What happened

Built the deterministic tag→constraint layer over S1.2's existing constraints hook.

- `backend/app/routing/profiles.py` (new) — `constraints_for_profile(profile, thresholds)`, a
  pure, total, order-independent mapping table. Plus `find_profile()`.
- `RoutingConstraints` gained two additive soft fields, `stair_penalty_m` / `window_penalty_m`
  (default 0.0 → pre-S3.4 behaviour bit-for-bit). Engine honours them in `_edge_cost`.
- `compute_route_plan(..., profile=...)` derives constraints and stamps `RoutePlan.profile_id`.
- `/routes` gained optional `profile_id`. `docs/profile-constraint-mappings.md` (new) is the
  judge-facing rationale doc — every row traced to a corpus line.
- Tests: `tests/test_profiles.py` (new, 14) + 4 `/routes` profile cases in `test_api.py`.

**Acceptance verified:** `python3 -m pytest` from backend/ → **120 passed, 6 deselected**
(was 106; the 6 deselected are the pre-existing `live`-marked AI tests). `corpus/validate.py`
still clean. The demo moment works on twostory: **Grandpa** (`mobility_limited`, master bedroom
upstairs) → `primary = None` + `no_viable_route`; **Maya** (`child`, kids' bedroom) → out via
`d_front`, 14.19 m. Different answers, straight from the deterministic engine.

## Decisions / surprises

All four rows promoted to `docs/decisions.md`. The ones worth reading:

- **Surprise (good): S3.4 needed no schema change.** `Profile` and `HomeModel.profiles` already
  existed from S0.2, `twostory.json` already ships Maya and Grandpa, and
  `corpus/special-considerations.md` *already spells out every tag mapping* with citations. S0.2
  and S0.4 did this session's design work months early — I implemented the corpus's table rather
  than inventing one. Judges asking "who decided that?" get pointed at USFA/NFPA.
- **Hard vs soft constraints** is the real design content. `mobility_limited` must *remove*
  stair/window edges (an unusable route is worse than an honest flag); `elderly` must only make
  them *cost more* (corpus says "prefer... where available" — a hard ban would fake a
  no-viable-route flag). Getting this wrong in either direction is a safety claim we can't back.
- **Surprise (bad), and I did not hide it:** the `child` window penalty changes **zero** routes
  on all three fixtures — the universal 12 m window penalty already dominates every door/window
  choice they contain. The child tag's only observable effect today is S3.1 explanation phrasing.
  There's a test asserting the no-op (`test_child_penalty_is_a_no_op_on_the_current_fixtures`) so
  it can't get quietly overclaimed in the demo video. `elderly` and `mobility_limited` are real:
  both change twostory outcomes.
- The 10.0 / 20.0 penalty magnitudes are **engineering choices, documented as such**. The corpus
  gives no number for "prefer"/"deprioritize" and I refused to invent one and attribute it to
  NFPA. Each has one stated property (10.0 > `STAIR_TRAVERSAL_COST` 6.0; 20.0 stacks to 32 with
  the universal window penalty).
- Playbook's "age band" and the prompt's `hearing_impaired` tag are **not implemented** — both
  need a `schema_version` bump + sign-off, and neither is routing input (`hearing_impaired` is
  alarm guidance → S3.5 checklist). Flagged, not silently dropped.

## Questions for teammates

- **@P2** — `/routes` now takes `profile_id` (not constraints); the mapping table stays
  server-side so the app can't fork it. Profile switch = re-POST `/routes` with a new
  `profile_id` and redraw. Response carries `profile_id` + `constraints` back so you can show
  *why* a route looks the way it does. Does that fit the plan-screen selector you're building?
- **@P1** — the two penalty magnitudes are my judgement calls, not corpus values. Sanity-check
  them? Also: are you OK with 422-on-conflict / 404-on-unknown-id rather than fall-back?
- **@P1/@P2** — Grandpa's `no_viable_route` on twostory is the honest, powerful answer, but it
  means the demo's "watch the path change" beat is *Maya's route vs Grandpa's red flag*, not two
  animated paths. Worth confirming that's the shot we want before S5.1 scripts it.

## Next steps

1. **@P2 — iOS profile CRUD UI** (name/tags/bedroom picker) + plan-screen profile selector.
   Out of scope here; needs S2.3's renderer.
2. **@P2 — live 3D re-fetch** on profile switch, and a `no_viable_route` treatment in the UI
   (Grandpa's case must render as a high-severity flag, not an empty screen).
3. Handoff artifact — the "recording of the live switch" the playbook asks for — is blocked on
   1 and 2; can't be produced from this lane.
4. Merge `s34-profiles` (backend-only diff; touches `routing/plan.py` + `engine.py`, so land it
   before or after `s35-score` deliberately, not concurrently).
5. Reconsider the `child` penalty once a fixture exists with a close door/window call — or drop
   the field and keep child as explanation-only, which is arguably more honest.
