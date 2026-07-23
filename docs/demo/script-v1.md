# Demo video script — **v1**

> **Status: WORKING SCRIPT** (supersedes `script-v0.md`, drafted 2026-07-16). Updated
> 2026-07-22 against the real build: S2.1/S2.2/S2.3/S3.1–S3.5 are code-complete and
> integrated, the backend is deployed, and the automated gate is green (115/115 EditorCore,
> full iOS suite on simulator, 195 backend tests). Most of v0's `[PENDING]` tags are resolved.
> **Not locked** until the two acceptance boxes at the bottom are checked by the team.
>
> **How to read the tags:** every factual claim is now either **true of the build today** or
> tagged `[PENDING: S<x>.<y>]` — a promise the named session must deliver before we say it on
> camera. Separately, `[FOOTAGE]` marks lines whose *visual* isn't captured yet (Worktree 4 is
> recording b-roll now — canonical paths in `storyboard-v1.md`). If a PENDING session gets cut
> (cut order: S4.2 drill → S3.3 chat → S3.5 score → camera tour → simplified agent), delete the
> line — do not soften it.
>
> **Target:** table-read under 3:15. VO measured at 150 wpm.
> **Tone:** talking to a parent about their house. Plain, warm, specific. No "leveraging AI",
> no "revolutionary", no "cutting-edge". Numbers only if they're in `backend/corpus/`.

**Total VO: 436 words ≈ 2:54 at 150 wpm.** ~21s of slack for pauses and the two silent beats
(the route animation and the montage breathe without narration). Re-count after any edit.

---

## Beat 1 — Hook (0:00–0:22, 56 words)

> **VO:** When a smoke alarm goes off, you may have as little as two minutes to get out.
> Two minutes, in the dark, with everyone half-asleep.
>
> The Red Cross says only about a quarter of families have made an escape plan and actually
> practiced it. Our families were in the other three quarters. So we built this.

**Claims — all true now, all cited from `backend/corpus/fire-facts-stats.md`:**

| Claim | Source id | Corpus line |
|---|---|---|
| "as little as two minutes to escape" | `redcross-two-minutes` | fire-facts-stats.md § Time to escape |
| "only about a quarter of families have developed **and practiced** a plan" (26%) | `redcross-escape-fact-sheet` | fire-facts-stats.md § Planning gap |

Rules (from `.claude/rules/paths/corpus.md`): round the way the source rounds, don't combine
the two numbers into a new claim, and **do not add a statistic that isn't in the corpus**.
On-screen: source attribution supers, so the citations are visible, not just spoken.
`[FOOTAGE]` night house / smoke alarm B-roll — shootable today, no app dependency.

---

## Beat 2 — The honest scan (0:22–0:52, 64 words)

> **VO:** It starts with your phone. You walk your home the way you'd walk a guest through it,
> and the LiDAR sensor builds the shape of the place — rooms, doors, windows.
>
> It gets us most of the way there in a few minutes. It also gets things wrong. It misses a
> window. It guesses at a doorway. So we never pretend the scan is finished.

**Resolved from v0:** the unsourced "eighty percent" is gone, per the honesty note in v0 and
`docs/decisions.md` (S5.1 draft entry) — S1.5's calibration never produced a measured number,
so we say "most of the way there" and don't invent one. If S1.5's real-export pass ever
produces a defensible figure, it may return *with* that figure.

**True now:** the converter exists and passes its tests against three synthetic RoomPlan
fixtures (`backend/app/convert/`); low-confidence items carry a `confidence` score and are
flagged rather than dropped — that schema invariant is the "we never pretend the scan is
finished" line. `[PENDING: S1.4]` a capture session on a real LiDAR device (the one shot that
can't be faked) · `[PENDING: S1.5]` conversion of that real export. `[FOOTAGE]` capture take
— owner P2, needs device + home.

---

## Beat 3 — The editor (0:52–1:20, 64 words)

> **VO:** Which is why the scan is the starting point, not the answer. Everything it flagged,
> you fix — drag a wall, drop in the window it missed, connect the stairs it couldn't see.
>
> That meant building a full 3D home editor, which is not what we expected to spend our summer
> on. But a plan built on a wrong map is worse than no plan.

**Resolved from v0 — true now.** S2.1 (editor core, 89 tests) and S2.2 (opening drag, stair
authoring, undo/redo) are code-complete and green on a real simulator. The claim under the
claim still holds: openings are stored parametrically against a wall segment (`edge_index` +
`t0/t1`), which is *why* dragging a wall carries its doors along — in
`schema/homemodel.schema.json` and enforced in `backend/app/models.py`. `[FOOTAGE]` wall-drag
with doors following (*the* shot), flagged → fixed.

---

## Beat 4 — The money shot (1:20–1:48, 40 words + ~10s of silence)

> **VO:** Then it does the thing we actually built it for.
>
> Every room gets a way out. And a second way out, through a different exit — because that's
> what fire safety guidance actually asks for.
>
> *(let the animation play — no narration)*

**Resolved from v0 — true now.** S1.3 (SceneKit dollhouse) and S2.3 (route overlay: animated
primary pulse tube, dashed secondary, warning badges, room picker, camera tour) are built and
tested. The routing engine computes exactly what the VO says: primary and secondary from every
room, secondary forced through a *different* exit (`backend/app/routing/`, samples in
`docs/route-samples/`). "Different exit" is our reading of NFPA's two-ways-out guidance
(`nfpa-escape-planning`), recorded in `docs/decisions.md` (S1.2). `[PENDING: camera tour]`
stays 4th in the cut order — if cut, hold the dollhouse orbit instead. `[FOOTAGE]` dollhouse
orbit + secondary-route reveal.

---

## Beat 5 — The inspector and the profile switch (1:48–2:24, 91 words)

> **VO:** Our AI inspector walks the model the way a fire marshal would. On our own test home,
> it found the kids' room has one door and one window — and that window is too small to climb
> out of. That's the room you'd have found out about at 2 a.m.
>
> And a plan for you isn't a plan for your grandmother. Switch profiles, and the routes change:
> no windows, no stairs, the ground-floor door instead.
>
> The AI explains and it inspects. It never picks the route. The route is math we wrote.

**Resolved from v0 — true now, with two accuracy rails (keep both, judges check):**

1. **Say "that window is too small to climb out of" — never "no second way out."** The
 engine's `no_secondary_egress` finding does *not* trip for the twostory kids' room (the
 house-level router legitimately routes out a different downstairs door); what's true is the
 window itself fails IRC R310 egress — 0.4 m wide vs the 0.508 m minimum, 0.4 m² vs 0.53 m²
 — caught by the agent's `check_egress` tool (`docs/decisions.md`, S3.2 entry). The VO above
 is worded to match exactly what the build reports.
2. **The profile that changes routes on camera is `mobility_limited` (grandmother), and
 the switch is one continuous take.** `mobility_limited` (hard avoid-stairs/avoid-windows)
 and `elderly` demonstrably change twostory routes; the `child` profile changes **zero**
 routes on all three fixtures — locked by a test — so we never claim it does.

S3.2 (agent loop, 6 tools, evidence validated server-side), S3.4 (profiles end-to-end: the
PlanScreen "Who" picker re-fetches `/routes` live), and S2.3 are code-complete.
`[PENDING: live API key]` — Render has no `ANTHROPIC_API_KEY` yet, so the inspector must be
filmed against a keyed backend (or local run with the key set). `[FOOTAGE]` findings
populating + tool-call trace; profile switch continuous take.

**The last line is the whole pitch — do not cut it.** It's the answer to "isn't this just an
AI wrapper?": routing is deterministic Python we wrote; the AI explains, chats, and audits,
grounded only in a curated FEMA/NFPA/Red Cross corpus, and every safety claim it makes is
checked against a real source server-side before it reaches you.

---

## Beat 6 — Montage (2:24–2:44, 41 words over fast cuts)

> **VO:** A preparedness score that tells you why, not just a number. A checklist that's about
> your house, not a generic list. And a drill you can actually run with your kids on a Saturday,
> timed, so you find the problems now.

**Score + checklist resolved — true now.** S3.5 shipped `/score` and the iOS score screen with
the component breakdown ("tells you why": 30 primary / 25 secondary / 20 findings / 15 alarms /
10 practice) and live re-scoring per checklist toggle. AI recommendations are deliberately
**non-scoring** — the honest answer to "isn't the score just the AI's opinion?" Caveat for the
edit: the findings component reads full marks until `/analyze` is wired into the score flow —
film the score after an analyze run, or crop the findings row.

**Drill still pending:** `[PENDING: S4.2]` — not started, first in the cut order. If it's cut,
delete the drill sentence (last 24 words); the beat still works at two features.

---

## Beat 7 — What we learned, what's next (2:44–3:06, 80 words)

> **VO:** Three of us built this. We wrote the routing engine ourselves — the graph, the path
> search, the code thresholds — because a safety app can't guess.
>
> The hardest part wasn't the AI. It was accepting that a scan is never quite right, and
> building the editor to fix it.
>
> Next: Android, and capture without LiDAR, so this works on the phone you already have. Then
> other disasters.
>
> Two minutes is not much time. It's enough, if you've thought about it first.

**True now.** Team roles per `CLAUDE.md`: we wrote the deterministic routing engine; the AI
explains and audits, it never computes routes. Android, camera-only capture, and other
disasters are deliberately out of scope — say them as future work, never as features.
`[FOOTAGE]` team on camera (one frame); cutaway of a live terminal run of
`python3 -m app.routing plan ../schema/fixtures/twostory.json --pretty` — recordable today.

---

## Truth ledger — every claim, its status, its evidence

| # | Claim (as spoken) | Status | Evidence |
|---|---|---|---|
| 1 | "as little as two minutes to get out" | TRUE, cited | `[cite: redcross-two-minutes]` → `backend/corpus/sources.json` |
| 2 | "about a quarter of families… made and practiced a plan" | TRUE, cited (26%) | `[cite: redcross-escape-fact-sheet]` → `sources.json` |
| 3 | "LiDAR builds the shape — rooms, doors, windows" | TRUE (synthetic); real device pending | `backend/app/convert/` tests · `[PENDING: S1.4/S1.5]` |
| 4 | "most of the way there in a few minutes" | TRUE as characterization (no number claimed) | v0 honesty note; decisions.md S5.1 entry |
| 5 | "we never pretend the scan is finished" | TRUE | schema `source`+`confidence` invariant; flagged-not-dropped (decisions.md S1.1) |
| 6 | "drag a wall… drop in the window… connect the stairs" | TRUE | S2.1/S2.2 code-done, 115 EditorCore tests green |
| 7 | "a full 3D home editor" | TRUE | S2.1/S2.2 + SceneKit editor screens |
| 8 | "every room gets a way out… second way through a different exit" | TRUE | routing engine + `docs/route-samples/`; decisions.md S1.2 (NFPA two-ways-out) |
| 9 | route animation on the dollhouse | TRUE (code); footage pending | S2.3 overlay, 14 tests · `[FOOTAGE]` |
| 10 | "AI inspector… found the kids' window too small to climb out of" | TRUE via agent `check_egress` (0.4 m < 0.508 m; 0.4 m² < 0.53 m²) | decisions.md S3.2; `egress_thresholds.json` (`irc-2021-r310`) · needs live key |
| 11 | "switch profiles and the routes change" (grandmother) | TRUE for `mobility_limited`/`elderly` on twostory; child is a no-op — never claim it | decisions.md S3.4; `twostory.mobility-limited.routeplan.json`; PlanScreen "Who" picker |
| 12 | "AI never picks the route; the route is math we wrote" | TRUE by architecture | routing = pure Python engine; AI layer explains/audits only; server-side citation validation |
| 13 | "score that tells you why" | TRUE | S3.5 component breakdown; AI recs non-scoring (decisions.md S3.5) |
| 14 | "checklist about your house" | TRUE | S3.5 checklist w/ live re-score (findings-row caveat above) |
| 15 | "a drill you can run… timed" | **[PENDING: S4.2]** — delete if cut | S4.2 not started; cut candidate #1 |
| 16 | "three of us built this / we wrote the routing engine" | TRUE | CLAUDE.md roles |
| 17 | Android / camera capture / other disasters | TRUE as future work only | scope locks in CLAUDE.md |

**Uncited safety statistics: zero.** The only two statistics are in Beat 1; both ids resolve
in `backend/corpus/sources.json`. Nothing else in the script is presented as a statistic.

**Production caveats for the shoot:** (a) AI beats (5, and Beat 6's findings row) need
`ANTHROPIC_API_KEY` — unset on Render as of 2026-07-22, so film against a keyed backend or a
local run; (b) warm-up ping before any live-API shot (Render free tier cold-starts, see
`docs/playbook/99-operating-notes.md`); (c) editor edge-case placements have no geometric
containment checks (decisions.md S2.2) — keep on-camera edits to normal drags.

---

## Table read / acceptance — NEEDS THE TEAM, not self-checkable

- [ ] **Table-read under 3:15** — 436 words ≈ 2:54 at 150 wpm on paper, but the gate is a real
 read-aloud with the team. Recount on every edit; the montage and hook are where words creep in.
- [ ] **P1 tech-accuracy pass** — every claim above verified against the shipped build by P1
 (S5.1's designated reviewer), especially rows 10–11 of the truth ledger.

## Open questions for the team (carried from v0, still open)

1. Whose home do we scan? Real clutter beats staged — but the family has to be comfortable
 putting it on the internet.
2. Show a scan failure on camera (Beat 2's honesty) or just say it? Showing is braver and
 probably scores better with judges.
3. Beat 5's kids'-room finding: seeded `twostory` fixture or the real scanned home? Real is
 more affecting — but only if it actually has a finding.
4. On-camera team or voice-over only? Beat 7 lands harder with faces.
