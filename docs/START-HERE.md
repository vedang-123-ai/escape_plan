---
handoff_status: active
handoff_owner: Anish Yarrakonda
handoff_opened: 2026-08-05
---

# START HERE — the UI/UX finishing pass

> **This is the long-form brief. The board is [`tracker/BLOCKERS.md`](tracker/BLOCKERS.md)** —
> that is where status lives and where you record anything you find undone. Read this file for
> the *why* and the order; read the board for *what is currently open*.

> **Flip `handoff_status` to `closed` in the front-matter above when this is done.** That is the
> only thing that stops the session-start banner. Do not delete the banner hook to silence it —
> if the work is done, close it honestly; if it isn't, the nagging is the point.

**From Anish, to whoever picks this up next (human or Claude):**

The engineering is essentially finished. What is not finished is how the app *feels*, and that
is now the single largest gap between this repo and a submittable Congressional App Challenge
entry. Everything below is written so you can start in the next five minutes without reading
the whole playbook.

---

## 1. What is already done — do not rebuild these

Read this section before you touch anything. Several of these were deliberate decisions that
look like bugs if you don't know the reasoning, and the fastest way to waste this handoff is to
"fix" one of them.

| Area | State |
|---|---|
| **HomeModel schema** | Frozen. `schema/homemodel.schema.json` is the contract across Python, Swift and the renderer. Changing it needs a version bump and a clean `schema-contract-guardian` run — agent review, no human sign-off. A hook prompts on `Edit`/`Write` only. |
| **Routing engine** | Done and deterministic. `/routes` works on all four fixtures. Routes are computed in Python, never by the AI. |
| **3D dollhouse + editor** | Done. The "White Model" overhaul (2026-08-05) made walls opaque and shadow-casting, added SSAO, and replaced the exploded view with ghost-floor stacking. |
| **Camera feel** | Reworked 2026-08-05 — pan projection math, cached pinch anchor, one transform write, shared gesture driver, inertia, loosened limits. **Verified only by tests. Never touched by a human finger.** See §3. |
| **Colour system** | `escape_plan/Screens/Theme.swift` is the semantic scale. **Route orange is reserved for lit routes and exits only.** Seven screens used to use `.orange` for warnings; that is fixed and must stay fixed — chrome uses dark amber for advisories. |
| **People layer** | White figures with name pills, selected person takes accent green. One route colour per person was **considered and rejected** — four saturated hues is exactly what the White Model overhaul removed. |
| **App icon, launch screen, home thumbnails** | Done 2026-08-05. The launch screen has no logo on purpose (Apple HIG: it should look like the first screen, not a splash). |
| **Failure states** | `Networking/BackendFailure.swift` is the single classifier. 502 → "AI unavailable", no Retry button. 503 → busy, with Retry. `BackendFailureBanner` is the one notice component. |

Full history: `docs/decisions.md`. Status of everything: `docs/tracker/TODO.md`.

---

## 2. Before you build to a device — two things or you will lose an hour

1. **Create `escape_plan/BackendConfig.local.json`** with `{"bearer_token": "<the real token>"}`.
   It is gitignored and **still missing as of 2026-09-08.** Without it a fresh install reaches
   the deployed backend and gets **401 on everything**. The app is not broken; it is
   unauthenticated. Ask Anish for the token.
2. **Run `python3 scripts/demo-preflight.py`.** It checks the token file, `/health` (Render's
   free tier sleeps — a ~30–50 s cold start reads as a broken app), whether the *deployed*
   schema matches this checkout, `/routes`, `/score`, and `/explain`. Exit 0 means the backend
   is actually ready.

**The deployed backend is current** — verified 2026-09-08: schema 2.0, all nine routes including
`/evacuate`. Do not spend time redeploying it. And note that `/health`'s `v1.0` is a hardcoded
FastAPI version, not a deploy signal; it caused a wrong "stale backend" diagnosis on 2026-09-07.

**Known-dead, do not debug:** the Anthropic account is out of credits, so `/explain`, `/analyze`
and `/chat` return **502** by design. The AI half of the app is dark until someone tops up the
balance. This is a billing problem, not a code problem — if you find yourself reading
`backend/app/ai/`, stop.

---

## 3. The actual job, in order

The test suite is green and proves nothing about feel. `xcodebuild` cannot tell you whether a
drag tracks your thumb. **Everything in this section requires a physical iPhone.**

### 3a. Camera feel — do this first, it gates everything else

The camera was reworked but never held. Four checks, in this order:

1. **Put a corner of the house under your thumb and pan.** It must stay under your thumb — in
   both orientations, and in both projections. **If this fails, stop and report it.** It means
   the projection branch is reading the wrong camera and nothing downstream is worth tuning.
2. **Pinch.** The point between your fingers must not crawl.
3. **Flick to orbit.** It must coast and ease out, not stop dead.
4. **Pan to the edge.** The rubber band must spring back visibly, not snap.

Then tune by feel. The current numbers are a starting guess, not a result:
apron `0.6`, distance `0.35…4.0 × extent`, orbit rate `0.6 π`, axis-lock `20 pt`
(`CameraRigModel` + `OrbitCameraRig`). **Orbit rate and axis-lock threshold interact — move
them together.**

### 3b. Frame rate — measure, don't guess

Nobody has ever profiled this on hardware. MSAA 4X, SSAO and the route pulse shader all run
during gestures. Measure frame time on the oldest phone you have, on **all four** fixtures
(bungalow, apartment, twostory, jagged). If it's the binding constraint, the levers are already
isolated behind `CameraGestureDriver.onPhaseChange` — drop MSAA to 2X during gestures and/or
disable SSAO mid-gesture. **Do not touch them without a measurement**; both are visible changes.

Also check **orthographic framing on a real phone specifically.** `orthographicScale` is a
half-*height*, so the portrait aspect correction is the difference between a framed house and
one cropped at both sides — and it is invisible on a square-ish simulator window.

### 3c. Walk the golden path on the device and write down every rough edge

Onboarding → build or open a home → routes render → switch profiles → drill → score. Do it as a
judge would, not as the person who built it. Note every moment you hesitate, every label you
have to re-read, every tap that does nothing. That list *is* the polish backlog — file it in
`docs/tracker/TODO.md`.

Specific known gaps worth folding in:
- `setOpeningWidth` exists in the reducer, fully tested, with **no UI entry point.** Add a width
  control to the opening inspector in `HouseScreen`.
- Tapping a person figure in the 3D view doesn't select them. `PeopleLayer.profileID(forHit:)`
  exists and is tested; it needs an `onPersonTapped` hook in `UnifiedSceneController` next to
  `onFloorTapped`.
- Floor toggling on-device: chips *and* tapping a ghosted floor, with the 0.35 s focus glide.
- Haptics — the simulator cannot verify a single one.

### 3d. Then, and only then, make it beautiful

With the feel fixed and the roughness listed, do the visual pass: spacing, type hierarchy,
empty states, transitions, loading states, the moments where the app currently just sits there.
Use the `ui-ux-pro-max` skill. Keep it inside `Theme.swift`'s semantic scale — **do not
introduce new colours, and do not put route orange in chrome.**

---

## 4. Rules that do not bend

- **Never re-enable `allowsCameraControl`.** The rig exists because SceneKit's default camera
  control was wrong for this app.
- **Keep `CameraRigModel` pure** — no SceneKit, no UIKit. It is symlinked into a Foundation-only
  SwiftPM package and will fail to build otherwise.
- **No API keys or bearer tokens in source.** A pre-commit hook blocks Anthropic key material.
- **Trust `xcodebuild`, never the editor.** SourceKit and VS Code cannot index this project and
  will report errors that do not exist. Ignore them completely.
- **A red iOS run may be noise.** Runs are ~1-in-3 flaky at launch (`Application failed
  preflight checks`, and a second face where the tab-bar button goes stale mid-tap). **Re-run
  before believing a red.** True test counts come from
  `xcrun xcresulttool get test-results summary --path <bundle>`, not the console tail.
- **Every session that changes a file must** update `docs/tracker/TODO.md`, write a note in
  `docs/tracker/notes/` (copy `_TEMPLATE.md`), and log any deviation in `docs/decisions.md`.
  No note, no DONE.

---

## 5. Done means

- [ ] All four camera checks in §3a pass on a physical phone, and the constants have been tuned
      by hand rather than left at their guessed values.
- [ ] Frame time measured on hardware on all four fixtures, with the number written down in
      `docs/tracker/TODO.md` — not "feels fine".
- [ ] The golden path walked end-to-end on a device with no dead taps and no unexplained waits.
- [ ] The rough-edge list from §3c is filed in [`tracker/BLOCKERS.md`](tracker/BLOCKERS.md), and
      the ones that would read badly on camera are fixed.
- [ ] `/verify` green, `BLOCKERS.md` updated, session note written.
- [ ] `handoff_status` above flipped to `closed`.

Remaining after this: top up the Anthropic account, then film the demo. Deadline is
**Oct 24, 2026.**

**The LiDAR field trip is done** — 2026-09-08, first attempt, a friend's house mapped correctly
and the routes animated well on the result. That was the project's largest untested hardware
dependency and it is now closed; `tracker/field-test-lidar.md` stays as the procedure if a
second trip ever happens.
