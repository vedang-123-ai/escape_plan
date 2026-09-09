# Field test — LiDAR scan → HomeModel

> **✅ THE TRIP HAPPENED — 2026-09-08, and it worked on the first attempt.** A friend's house
> was scanned, RoomPlan mapped it correctly, the conversion held, and the routes animated well
> on the result. The "built but unverified" framing below is **historical**. What is still open
> is only artifact capture — committing a clean and a messy export to `schema/fixtures/scans/`,
> and promoting the assumed-format risks in `backend/app/convert/README.md` into
> `docs/decisions.md` now that a real export has shown which assumptions held. Neither blocks
> the demo. This file stays as the procedure for a second trip.

_Written 2026-08-05. A runnable script for the one device trip that closes S1.4 and S1.5._

## Why this exists

The scan pipeline is **built but unverified**. `Capture/Export/` produces the export,
`backend/app/convert/roomplan.py` converts it, `/convert` serves it, and there are four
synthetic fixtures with passing tests. What has never happened is a real phone pointed at a
real room.

That matters more than "one more test" because of this line in
[backend/app/convert/README.md](../../backend/app/convert/README.md):

> Built against an ASSUMED input format, validated only on synthetic fixtures. S1.4's real
> device exports must be diffed against this document before S1.5 can be called DONE.

The synthetic fixtures were generated from the same assumptions the converter was written
against, so they cannot falsify those assumptions — they agree with the converter by
construction. Only a real export can disagree. **The first question this trip answers is not
"did conversion work?" but "does the format match?"**, because the worst failure mode
(row-major transforms) converts without raising and silently produces a house made entirely
of bounding boxes.

Budget: ~1 h on site, ~2 h at the desk. Two trips if the first one finds a converter bug.

---

## Gate 0 — hardware

You need **LiDAR**: iPhone 12 Pro / Pro Max or any later *Pro*, or an iPad Pro (2020+).
Base and Plus iPhones have no LiDAR sensor and `RoomCaptureSession.isSupported` returns
false — the app degrades gracefully to the "not supported" screen, which is correct
behaviour and tells you nothing.

If you don't have one, borrow one. There is no software substitute; the simulator has no
LiDAR, which is why every item in the "Needs real LiDAR hardware" block of
[TODO.md](TODO.md) has been open since 2026-07-16.

---

## Part 1 — at the desk, before you leave

Do not discover a signing problem in someone else's apartment.

1. **Install to the device from Xcode.** Select the physical device as the run destination
   and Run (`xcodebuild` with `CODE_SIGNING_ALLOWED=NO` builds for the simulator only —
   device installs need real signing). Bundle id is `cac.Escape-Plan`. On a free personal
   team the provisioning profile **expires after 7 days** — if the trip is more than a week
   out, plan to reinstall.
2. **Confirm the scan entry point is reachable** and that the instruction screen appears —
   not the "not supported" screen. If it says unsupported, the device has no LiDAR (Gate 0).
3. **Put the bearer token in `escape_plan/BackendConfig.local.json`**
   (`{"bearer_token": "..."}`, gitignored) or the in-app upload to `/convert` will fail with
   the token banner. The triage loop in Part 4 doesn't need it — but the in-app round trip in
   Part 6 does.
4. **Sanity-check the triage tool** on a known-good fixture so you know what "clean" looks
   like before you're staring at real output:

   ```bash
   cd backend
   python3 scripts/triage_scan.py ../schema/fixtures/scans/synthetic-bungalow.roomplan.json
   #  → 0 FAIL · 0 WARN, exit 0
   python3 scripts/triage_scan.py ../schema/fixtures/scans/synthetic-messy.roomplan.json
   #  → 0 FAIL · 3 WARN, exit 1   (low confidence + flagged openings, by design)
   ```

5. **Charge the phone.** RoomPlan runs the LiDAR, the camera and ARKit tracking at once.

---

## Part 2 — on site

Scan a space with **2–3 rooms connected by a door**, one of which has an exterior door and at
least one window. A two-bedroom apartment or a kitchen/hall/living run is ideal. S1.5's
acceptance needs ≥1 exterior door and ≥1 window mapped, and the interior door is what
exercises shared-door adjacency — the assumption most likely to be wrong.

**Before you start capturing:**

- Open every interior door fully. RoomPlan classifies a closed door as wall. No door → no
  adjacency → no route.
- Turn all the lights on. LiDAR handles the geometry but ARKit's tracking is visual, and
  poor light means drift.
- Pull curtains and blinds open so windows read as windows.
- Clear the walls where you reasonably can. Furniture against a wall is the main cause of
  a wall being detected short.

**Capture technique:**

- Stand ~1.5–2 m from the wall you're pointing at. Closer than ~0.5 m and the depth data
  is unusable; further than ~5 m and it thins out.
- Walk the perimeter of each room slowly, panning across the wall/ceiling junction. Rushing
  corners is the single most common cause of an unclosed polygon.
- Pause 2–3 s on each door and window.
- Walk *through* the doorway between rooms rather than turning around in it — that
  continuity is what lets the merged `CapturedStructure` API pair the two sides of the door.
- Keep going until the on-screen geometry stops changing, then finish.

**Capture three scans, in this order:**

| # | What | Purpose |
|---|---|---|
| 1 | **Clean** — the careful scan above | S1.4 + S1.5 primary acceptance; the demo asset |
| 2 | **Repeat** — scan the same space again immediately | S1.4: "a second full scan completes without crashing" |
| 3 | **Messy** — deliberately bad: rush it, leave one door closed, skip a wall, poor light | S1.5: degrades with low-confidence flags instead of crashing |

After each scan, the review screen prints the artifact directory name at the bottom in
monospace. **Write it down** — that's how you find it later.

---

## Part 3 — get the files off

Each scan lands in the app's documents directory as one self-contained folder:

```
Documents/Scans/<yyyyMMdd-HHmmss>-<short-id>/
    raw.roomplan.json    ← the converter's input (our pinned format)
    apple-raw.json       ← Apple's own CapturedStructure encoding
    scan.usdz            ← parametric USDZ, for eyeballing the capture
```

Copy the whole folder off via Files.app → On My iPhone → Escape Plan, or Finder → device →
Files. Land them under `artifacts/scans/` (gitignored) to start; only curated copies go into
`schema/fixtures/scans/` later.

**Open `scan.usdz` in Quick Look before you look at any JSON.** It shows what RoomPlan
actually saw. If the USDZ is already wrong, the converter is not your problem — rescan.
This is also the "RoomPlan USDZ vs rendered HomeModel" side-by-side that S1.5's handoff asks
for, so screenshot it.

---

## Part 4 — triage (do this before touching any code)

```bash
cd backend
python3 scripts/triage_scan.py ../artifacts/scans/<scan-dir>/raw.roomplan.json \
        --json-out ../artifacts/scans/<scan-dir>/home.json
```

The script checks the format assumptions first, converts second, and names the symptom when
a known failure mode fires. It reports:

- **Input shape** — `CapturedStructure` vs single `CapturedRoom`, and which keys are ignored.
- **Format assumptions** — transform majorness (the big one), `dimensions` shape, confidence
  encoding, `parentIdentifier` presence, curved walls, multi-story exports.
- **Converted model** — every room with vertex count, area and confidence; every opening
  with its rooms and whether it's an exit.
- **Acceptance signals** — ≥1 exterior door, ≥1 window, interior doors paired, bbox
  fallbacks, flagged-for-review items.
- **Idempotency** and **contract validation** (JSON Schema + pydantic).

Exit code: `0` clean · `1` warnings worth reading · `2` FAILs that must be fixed in
`app/convert/roomplan.py` before anything downstream is trustworthy.

### The loop, when something is wrong

1. Copy the offending export into `schema/fixtures/scans/` under a real name
   (`real-<space>-<clean|messy>.roomplan.json`).
2. Write a **failing test** in `backend/tests/test_convert.py` asserting what the export
   should produce.
3. Fix `app/convert/roomplan.py` until it passes. Pure functions, no I/O, no server, fast
   loop — this is why the converter was built that way.
4. Re-run the whole suite: `python3 -m pytest backend/tests/ -m "not live"`. The synthetic
   fixtures must stay green; a fix that breaks them is a fix in the wrong place.
5. Record the real failure mode in `docs/decisions.md` — S1.5's handoff explicitly asks for
   the list of known failure modes, and the ones a real export found are worth more than the
   predicted ones.

### Symptom → cause

| Symptom in triage output | Almost certainly |
|---|---|
| `transforms look ROW-major` | The `simd_float4x4` flattening assumption is inverted. Fix this first — everything downstream is garbage until it's right. |
| Every room boxy **and** low confidence | The bbox fallback is firing everywhere; usually a downstream effect of the row above, or wall chaining failing on gaps > 0.25 m. |
| Multiple rooms, **zero interior doors** | Shared-door pairing didn't fire. Check whether the two sides share an `identifier` (merge dedup) or need the geometric matcher (0.35 m / 25° tolerances). Every door reading as an exit is the tell. |
| No exterior door | A door was closed during capture, or the whole scan is interior. Rescan. |
| No windows | Blinds closed, or glass at an angle LiDAR skipped. Rescan. |
| `no sections labels` | RoomPlan didn't classify room types. Not a bug — rooms come out as `other`/"Room N" and the user renames them in the editor. Worth knowing before you film. |
| Multiple `story` values | v1 assumes one floor per scan session. Scan each floor separately, join with stairs in the editor. |
| `convert_scan raised …` | A real converter bug — it is supposed to degrade, never crash. Failing test first. |
| Room polygon has many vertices / weird area | Near-collinear merge (8°) or rectangularize (12°) thresholds don't suit real walls. Tune with the real fixture as the test. |

---

## Part 5 — the in-app round trip

Triage proves the converter. This proves the *product*.

1. In the app, run a scan and continue through to the editor — this exercises the real
   `/convert` upload path, not the Python function.
2. Confirm the model renders in the 3D dollhouse.
3. **Find one misplaced door on the real converted scan and fix it in under 2 minutes.**
   That's an S2.x acceptance criterion and it is also the single most persuasive thing in
   the demo video: the scan is a draft, the editor is the corrector, and a judge watching
   you fix it understands the architecture instantly.
4. Confirm flagged low-confidence items actually surface in the editor.
5. Compute routes on the real home and confirm they're sane.

---

## Part 6 — what to commit

- Two curated exports in `schema/fixtures/scans/` — one clean, one messy (S1.4's handoff).
  Scrub nothing; they're geometry, not photos. Sizes are small (the synthetics are 4–9 KB;
  real ones run larger but still modest).
- Any converter fixes, each with the test that caught it.
- The USDZ ↔ rendered-HomeModel side-by-side screenshot into `docs/evidence/S1-5/`
  (S1.5 handoff; keep it under 1 MB).
- `docs/decisions.md` — which format assumptions held, which didn't, and the real failure
  modes list.
- A session note in `notes/`, and strike the closed lines from `TODO.md`.

## What this closes

| Criterion | Session | Closed by |
|---|---|---|
| Scan a real 2–3 room space; raw JSON has walls/doors/windows | S1.4 | Part 2 scan 1 + Part 4 surface counts |
| A second full scan completes without crashing | S1.4 | Part 2 scan 2 |
| Clean + messy exports committed to `schema/fixtures/scans/` | S1.4 | Part 6 |
| Clean scan → valid HomeModel, ≥1 exterior door, ≥1 window | S1.5 | Part 4 acceptance signals |
| Messy scan → valid model, low-confidence flags, no crash | S1.5 | Part 2 scan 3 + Part 4 |
| Conversion is idempotent on a real export | S1.5 | Part 4 idempotency |
| Known failure modes documented from real exports | S1.5 | Part 4 loop step 5 |
| Fix a misplaced door on a real scan in < 2 min | S2.x | Part 5 |

---

## If the trip goes badly

Two failure grades, two different responses.

**RoomPlan captured fine but the converter is wrong.** Good outcome, actually — you have a
real fixture and a fast pure-Python loop. Fix it. This is a normal afternoon.

**No LiDAR device available before the deadline.** Then the demo leads with the *editor* and
presents scanning as beta. An organizer has confirmed a pre-captured or hand-built model is
acceptable in the submission video provided the demo is described accurately — so record the
scan segment once when you do get hardware, or say plainly that the model was built in the
editor. The line that must not be crossed is narration claiming a scan produced a model it
didn't; "scanned earlier" over pre-recorded footage is fine and is how every product demo on
earth is made. Note that per the cut order in `CLAUDE.md`, scan → editor → 3D routes →
profile switch is explicitly the part that is **never** cut — so the fallback is a change of
emphasis, not a change of scope.
