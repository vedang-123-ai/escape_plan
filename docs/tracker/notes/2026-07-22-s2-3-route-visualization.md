# S2.3 — Route visualization on the 3D model

- **Who:** P3 (Claude Code), covering the code half of a P2 session
- **Date(s):** 2026-07-22
- **Status when I stopped:** code complete, all 14 new tests + full existing suite green on the iPhone 17 Pro simulator; device eyes-on pass (animation smoothness, tour feel, the acceptance recording) still open — same posture as S1.3.

## What happened

Built the full S2.3 stack on top of the just-landed PlanScreen dollhouse integration:

- `Models/RoutePlan.swift` — snake_case Codable mirror of `backend/app/routing/plan.py`
  (`RoutePlan`/`RoomRoutePlan`/`Route`/`Waypoint`/`RouteFinding`/`Bottleneck` +
  `RoutingConstraints`), lenient on backend-defaulted keys so all four committed
  `docs/route-samples/*.routeplan.json` decode. `RoutesRequest` omits nil
  `constraints`/`profile_id` keys entirely (the backend 422s when both arrive).
- `Networking/APIClient+Routes.swift` — `fetchRoutes(home:constraints:profileID:)` following
  the `APIClient+Score.swift` extension pattern; 90 s timeout for Render cold starts.
- `Renderer/RouteGeometry.swift` — pure, tested: waypoints → per-floor runs (split at the
  double-stair-waypoint crossing), Catmull-Rom smoothing, arc-length tables, and a custom
  tube mesh (parallel-transport frames, arc-length-normalized `u` UVs).
- `Renderer/RouteOverlay.swift` — draws primary (warm, pulse shader driven by `u_time` and
  the arc-length `u`, so bands flow room → exit) and secondary (cool, alpha-dashed, +6 cm
  lift) tubes into per-floor `"routes:<floorID>"` containers under the builder's floor
  nodes, so explode/floor-hide work for free; glowing cone stubs mark stair crossings;
  pulsing shells glow on exit openings; billboarded `!`/`✕` badges render the engine's
  `no_secondary_egress`/`no_viable_route` findings. Camera tour flies the primary route at
  eye height via one `SCNAction.customAction` over the arc-length table, restores free
  orbit on finish/cancel.
- `PlanScreen.swift` — fetches `/routes` after each home load (no profile_id — base plan),
  room picker ("Everyone" = primaries + badges only; single room = both routes), tour
  button, non-blocking cold-start/error banners with Retry, findings strip quoting the
  engine's `detail` text verbatim.
- `DollhouseSceneView` gained three defaulted props (`wantsContinuousRendering`,
  `isTouring`, `onViewReady`); `DollhousePalette` gained the five route/warning colors.

Tests: `escape_planTests/RoutePlanTests.swift` — sample decoding (incl. the apartment
`no_secondary_egress` and mobility-limited `no_viable_route` cases), request-key omission,
floor-run splitting, smoothing/arc-length math, tube mesh counts + directional UVs, and
overlay scene-graph contract (per-floor parenting, badges, `clear()` restores node count).

## Decisions / surprises

(promoted to docs/decisions.md)

- Warning-badge acceptance runs on the **apartment** fixture — per the 2026-07-16 note, the
  twostory kids' room does NOT carry `no_secondary_egress` in the RoutePlan.
- No profile is sent in S2.3; there is no default-profile concept anywhere in the app. The
  call is parameterized so S3.4's live-switch TODO(integration) is now just UI.
- Stair crossings render as paired floor-local stubs, not a cross-floor tube — survives the
  exploded view with zero per-frame recompute.
- Secondary dashes are alpha-zero, not `discard` (SceneKit's GLSL→Metal transpile of
  discard is unreliable).

## Questions for teammates

- @P2: device pass please — pulse shader smoothness, tour feel (1.5 m/s, 1 m look-ahead),
  and the acceptance recording (twostory upstairs bedroom → both routes; apartment → badges).
- @P2: `sceneView` is handed out of `DollhouseSceneView` via `onViewReady` for tour control —
  shout if you'd rather a coordinator.

## Next steps

Device run: set Settings → base URL to `https://escape-plan-backend.onrender.com` + bearer
token, open Plan tab on a saved twostory home, record the acceptance clip (that recording is
the S2.3 handoff artifact). Then unblock S3.4's live route re-fetch and S4.1.
