# Demo video script — **DRAFT v0**

> **Status: EARLY DRAFT.** Written 2026-07-16, months before S5.1's real slot (S5.1 formally
> follows S4.1, which hasn't started). The point of drafting now is so the team edits a real
> script in October instead of writing one from zero. **Nothing here is locked.**
>
> **How to read the tags:** every factual claim below is either true of the build today or
> tagged `[PENDING: S<x>.<y>]` — meaning the line is a promise the script makes that the named
> session has to deliver before we can say it on camera. If a PENDING session gets cut
> (`CLAUDE.md` cut order: S4.2 drill → S3.3 chat → S3.5 score → camera tour → simplified
> agent), delete the line — do not soften it.
>
> **Target:** under 3:15 read aloud. Voice-over word count below is measured against 150 wpm.
> **Tone:** talking to a parent about their house. Plain, warm, specific. No "leveraging AI",
> no "revolutionary", no "cutting-edge". Numbers only if they're in `backend/corpus/`.

**Total VO: 438 words ≈ 2:55 at 150 wpm.** Leaves ~20s of slack for pauses and the two silent
beats (the route animation and the montage breathe without narration). Re-count after any edit.

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

Rules for this beat (from `.claude/rules/paths/corpus.md`): round the way the source rounds,
don't combine the two numbers into a new claim, and **do not add a statistic that isn't in the
corpus** — if the edit wants a punchier number, it goes through S0.4 with a real source first.
On-screen: source attribution supers, so the citations are visible, not just spoken.

---

## Beat 2 — The honest scan (0:22–0:52, 66 words)

> **VO:** It starts with your phone. You walk your home the way you'd walk a guest through it,
> and the LiDAR sensor builds the shape of the place — rooms, doors, windows.
>
> It gets us about eighty percent of the way there in a few minutes. It also gets things wrong.
> It misses a window. It guesses at a doorway. So we never pretend the scan is finished.

`[PENDING: S1.4]` — the RoomPlan capture flow on a real device. `[PENDING: S1.5]` — real-export
conversion to HomeModel. **True now:** the converter module exists and passes 18 tests against
three synthetic RoomPlan fixtures (`backend/app/convert/`), and low-confidence items are carried
with a `confidence` score and flagged rather than dropped — that's the schema invariant the
"we never pretend the scan is finished" line is describing.

**Honesty note (keep this, it's the beat's whole job):** the "eighty percent" is a
characterization of scan quality, not a measured benchmark. Before this is said on camera,
either (a) S1.5's calibration pass produces a real number and we say that number, or (b) we
reword to "it gets us most of the way there in a few minutes." Do not invent a percentage.

---

## Beat 3 — The editor (0:52–1:20, 64 words)

> **VO:** Which is why the scan is the starting point, not the answer. Everything it flagged,
> you fix — drag a wall, drop in the window it missed, connect the stairs it couldn't see.
>
> That meant building a full 3D home editor, which is not what we expected to spend our summer
> on. But a plan built on a wrong map is worse than no plan.

`[PENDING: S2.1]` editor core · `[PENDING: S2.2]` opening/stair editing. **True now (the claim
under the claim):** openings are stored parametrically against a wall segment (`edge_index` +
`t0/t1`), which is *why* dragging a wall carries its doors along — that invariant is in
`schema/homemodel.schema.json` and enforced in `backend/app/models.py` today.

---

## Beat 4 — The money shot (1:20–1:48, 40 words + ~10s of silence)

> **VO:** Then it does the thing we actually built it for.
>
> Every room gets a way out. And a second way out, through a different exit — because that's
> what fire safety guidance actually asks for.
>
> *(let the animation play — no narration)*

`[PENDING: S1.3]` SceneKit dollhouse + animated paths · `[PENDING: camera tour]` (first thing
cut after the score, per the cut order — if it's gone, hold on the dollhouse rotation instead).

**True now:** the routing engine computes exactly this. Primary and secondary routes from every
room, secondary forced through a *different* exit, bottlenecks identified — `backend/app/routing/`,
sample output committed in `docs/route-samples/` for all three fixtures. The "different exit"
rule is our reading of NFPA's two-ways-out guidance (`nfpa-escape-planning`) and is recorded in
`docs/decisions.md` (S1.2).

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

`[PENDING: S3.2]` agentic analysis · `[PENDING: S3.4]` family profiles · `[PENDING: S2.3]`
(profiles' prerequisite). **True now:** the egress checker already flags undersized windows
against IRC R310 thresholds (`backend/app/routing/egress.py`, `backend/corpus/egress_thresholds.json`),
non-viable windows survive in the graph as flagged dead ends rather than being dropped, the
`twostory` fixture is seeded on purpose with a too-small egress window, and a mobility-limited
route plan is already committed (`docs/route-samples/twostory.mobility-limited.routeplan.json`).
The grounded explanation layer with server-side citation validation exists and is tested
(`backend/app/ai/grounded.py`) — `[PENDING: S3.1 human step]` a live API run + P1's hand review.

**The last line is the whole pitch — do not cut it.** It's the answer to "isn't this just an AI
wrapper?": routing is deterministic Python we wrote; the AI explains, chats, and audits, grounded
only in a curated FEMA/NFPA/Red Cross corpus, and every safety claim it makes is checked against
a real source before it reaches you.

---

## Beat 6 — Montage (2:24–2:44, 41 words over fast cuts)

> **VO:** A preparedness score that tells you why, not just a number. A checklist that's about
> your house, not a generic list. And a drill you can actually run with your kids on a Saturday,
> timed, so you find the problems now.

`[PENDING: S3.5]` score · `[PENDING: S4.x]` checklist · `[PENDING: S4.2]` drill mode. This beat
is built from the three most-cuttable sessions — **write it last** and drop whichever lines
didn't ship. One line per feature, no lingering.

---

## Beat 7 — What we learned, what's next (2:44–3:07, 80 words)

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

**True now.** Team roles per `CLAUDE.md`. Android, camera-only capture, and other disasters are
deliberately out of scope and named as future work — say them as future work, never as features.

---

## Table read / acceptance

- **Word count: 438 words → 2:55 at 150 wpm.** Under the 3:15 gate with ~20s of headroom.
  Recount on every edit; the montage and hook are where words creep back in.
- **Uncited safety statistics: zero.** The only two statistics are in Beat 1 and both resolve to
  `sources.json` ids. Beat 2's "eighty percent" is flagged as a characterization to replace or
  reword — it is not presented as a sourced statistic.
- **Every claim tagged.** Beats 1, 4 (engine), 5 (egress/explanations), 7 are true today.
  Beats 2, 3, 6 and the visual halves of 4 and 5 carry `[PENDING: S<x>.<y>]`.

## Open questions for the team

1. Whose home do we scan? A real one, with real clutter, beats a staged one — but it has to be
   a home someone's family is comfortable putting on the internet.
2. Do we show a scan failure on camera (Beat 2's honesty) or just say it? Showing it is braver
   and probably scores better with judges.
3. Beat 5's "kids' room" finding: use the seeded `twostory` fixture, or the real scanned home?
   The real home is more affecting — but only if it actually has a finding.
4. On-camera team, or voice-over only? Beat 7 lands harder with faces.
