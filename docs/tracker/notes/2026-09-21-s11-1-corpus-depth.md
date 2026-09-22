# S11.1 — Earthquake + tornado corpus depth, and cited prevention tips

- **Who:** P3
- **Date(s):** 2026-09-21
- **Status when I stopped:** Done. Corpus **36 sources, 13 files, 2 threshold files, 44 tips**;
  `validate.py` green; backend **557 passed, 1 skipped, 13 deselected**.
  `check_urls.py`: **0 hard failures across all 36 sources, 17 content-verified** — those 17 are every
  source this session added or touched. The other 19 carry no `verify_keywords` (all the fire sources,
  plus the bot-walled and PDF ones) and are listed in `BLOCKERS.md`.

## What happened

The session was supposed to be "add depth". It turned into "add depth **and** repair attribution",
because the mission's own instruction — *fetch the URL yourself and stamp the date only after a 200 and a
content check* — failed on the sources already in the corpus.

**Four claims were attributed to pages that never carried them:**

| Claim | Was cited to | What that page actually has |
|---|---|---|
| Triangle of Life discredited; securing items; aftershocks; the gas-leak rule | `usgs-earthquake` | `usgs.gov/.../prepare` is a **link directory**. None of it. |
| Keep a wrench by the valve; don't restore gas yourself | `fema-earthquake` | `ready.gov/earthquakes` has **no gas content at all** |
| Drywall anchors inadequate; renter adhesive nylon straps | `shakeout-guidance` | Step 1 says "wall studs", "two metal straps", putty for small objects |
| Lowest floor; helmets; bed-shaker alerts | `noaa-tornado` | `weather.gov/safety/tornado-during` has none of the three |

`validate.py` was green over every one of them, because it checks that a cite **id resolves** — never that
the claim is **on** the page. That is a structural limit, not a bug: the gate is offline by design.

I put this to the owner before doing it. Ruling: repair and deepen, and add a URL checker.

**What I built, in order:**

1. `backend/corpus/check_urls.py` — opt-in, network, **not** in the gate. Re-fetches every source URL,
   confirms 200, greps per-source `verify_keywords`. Built first because every `retrieved` date after this
   point depends on it. It found a dead link on its first run (below).
2. **Repaired the attributions.** Six claims re-pointed to sources that carry them, two deleted outright
   (drywall anchors, renter adhesive straps). `earthquake-securing-home.md` says in the open that they
   were removed and why, and offers the renter guidance that *is* sourced instead.
3. **Earthquake 1 doc → 3**: during-shaking / securing-the-home / after-the-shaking.
4. **Tornado 1 doc → 3**: shelter-selection / safe-rooms / warnings-and-mobile-homes.
5. **9 + 2 new sources**, each fetched and keyword-checked before its date was stamped.
6. **`prevention_tips.json`, 44 tips** (fire 20, earthquake 13, tornado 11) against a target of 20.
7. **`validate.py` check 7** for the tips file, proven by breaking the file on purpose.
8. Rewrote `docs/corpus-summary.md`, which was stale by 24 sources.

**Method note worth keeping:** I stopped using WebFetch for authoring. It summarises through a small
model, which is fine for "does this page exist" and wrong for "what exactly does this page say" when the
output becomes a cited safety claim. Everything quoted in the new docs came from raw HTML pulled with
`curl` and stripped to text, or — for the FEMA PDF, which is bot-walled to scripts — from Quartz text
extraction of the PDF itself.

## Decisions / surprises

All four are in `docs/decisions.md` (2026-09-21). The two that will matter to someone else:

- **Earthquake and tornado add no numeric thresholds, and that is the finding.** Not a gap to fill later.
  The only two numbers the sources carry are not app-checkable: "two metal straps" is a practice rather
  than a dimensioned code value, and FEMA's 200–250 mph safe-room design wind speed is a *construction*
  criterion no phone or scan can measure. CA H&S §19211 makes strapping legally mandatory but delegates
  the method to the paywalled California Plumbing Code. **This absence is the substance of S11.2's
  `guidance_based` tier** — manufacturing a number to make scoring tidier is the exact failure the tiering
  exists to prevent.
- **No candle tips.** The USFA candles page is a 404. The mission asked for candle habits; citing an
  adjacent USFA page would be the same misattribution I spent the session removing.

**Surprises:**

- **`irc-2021-r311` was a 404** — and it is the source behind the egress-door 32×78 in thresholds the
  engine actually uses. It pointed at the chapter rather than the section. Nothing had re-fetched a source
  URL in the project's history, so it rotted silently. Fixed.
- **fema.gov rejects every scripted fetch** (urllib and curl, full browser headers included) while serving
  browsers normally, and **nfpa.org returns a ~40-character JS shell**. I made the checker report these as
  BLOCKED / NO-TEXT rather than FAIL — a permanently red run trains people to ignore it, which is how this
  repo's tracker drifted before.
- The Northridge/UCLA figure turned up while reading ShakeOut Step 1 and is genuinely useful: **55% of
  injuries from falling furniture, 1% from building damage.** That is the evidence for putting "secure
  your contents" ahead of structural work, and it is a real statistic for the pitch.

### The one I did not see coming

`backend/tests/test_ai.py::test_corpus_block_matches_sources_json` failed on my own work, and it was
right. I added `usfa-extinguishers` and `usfa-batteries` to `sources.json` so the **tips file** could cite
them — but the corpus block the model is shown is built from the **markdown docs**, and neither id
appeared in one. For one commit, the server would have accepted `usfa-extinguishers` on an extinguisher
claim the model made up, because `valid_source_ids()` reads `sources.json` while `corpus_text()` reads the
markdown.

That is the project's central law failing, in my diff, on the session whose whole theme was attribution.
`validate.py` cannot catch it — the ids resolve perfectly. The backend suite caught it. Fixed by giving
both sources a real home: the USFA extinguisher decision rule went into `escape-planning-nfpa.md` and
lithium-ion batteries into `heating-electrical-fire-safety.md`.

**Rule for anyone adding a source:** `prevention_tips.json` is not a corpus document for this purpose. A
new source id needs a markdown doc citing it in the same commit, and you find out by running the backend
suite, not the corpus validator.

### What the grounding-auditor found

Run at the end of the session. Verdict: the six new corpus documents are clean — every safety sentence
cites, all 44 tip cites resolve, the tiering in `tornado-safe-rooms.md` is explicit, no numeric threshold
was smuggled in, and the AI-never-routes invariants hold. **The defects were all at the edges**, and four
were worth acting on:

1. **The two claims I deleted are still shipping from `backend/app/scoring/checklist.py`** — and
   `:583` cites `shakeout-guidance` for the renter adhesive-strap claim, which is a **fabricated citation
   that validates**. The id resolves, so `validate.py` and the backend suite are both green over an
   attribution my own new doc says is false. Outside my OWNED FILES; logged in `BLOCKERS.md` as the
   highest item there, with every replacement string, the correct source, and the test that will go red.
2. **`usgs-earthquake` became an orphan** when I re-pointed the last doc that cited it — the exact hole I
   had written a rule against earlier the same session. Fixed properly: `validate.py` **check 8** now
   fails on any source id no corpus doc cites and no threshold file names. A paragraph in `decisions.md`
   was never going to hold that line. The one exception is documented *in the code* with its owner.
3. **Two docs claimed app behaviour that does not exist**, and that prose goes verbatim into the system
   prompt — so the model could have told a user the app detected something it never looks at. The
   tornado mobile-home section described an output the engine **deliberately does not produce**
   (construction type is not derivable from a footprint; the check was removed after misfiring on 4 of 5
   fixtures), and the earthquake kitchen line implied room scoring `perils/earthquake.py` does not have.
4. **My own `decisions.md` row miscounted itself** — "three re-pointed" above a list of six, and two
   deletions when there were four. Corrected with a new dated row, since the log is append-only.

Also dropped a tip's "a toppled heater can rupture its gas line" — the action is sourced, that mechanism
is on no page I fetched.

One auditor claim I checked and did not accept: it reported that
`test_corpus_block_matches_sources_json` only compares file lists. It does more than that — it also
asserts no valid source id is missing from the block, which is exactly how it caught my earlier hole. Its
real weakness is the one I had already logged: the check is a substring test, so an orphan whose id
prefixes another id reads as covered. Same conclusion, different reason.

## Questions for teammates

- **@P1 / @P2 (Lane B, S11.5):** tips file is `backend/corpus/prevention_tips.json`, shape
  `{"tips":[{"id","peril","topic","text","cite","audience"}]}`. `audience` values in use: `everyone`,
  `renters`, `households-with-children`, `mobile-home`, `deaf-hard-of-hearing`, `california`. The `id` is
  stable and safe to persist dismissals against. Bundle a byte-identical copy and wire
  `scripts/check-tips-sync.py` as your session says.
- **@whoever takes S11.2:** do not go hunting for earthquake/tornado numbers to encode. There are none;
  build those checklist items from the markdown. See the decisions row before you spend an hour on it.
- **Open question for nobody in particular:** the earthquake corpus leans Californian (ShakeOut, CA
  statute). Sound general practice everywhere and the legal section is labelled California-only, but worth
  a second state's equivalent if anyone has time.

## Next steps

1. **S11.2 is unblocked** — this was its prereq.
2. `check_urls.py` should be run before submission. 34 other URLs can rot the way R311 did.
3. The open S11.1 items in `BLOCKERS.md`: 19 of 36 sources still have no `verify_keywords` and cannot be
   content-checked — **every fire source is in that group.** This session verified the peril sources, not
   the fire ones. Whoever next touches the fire corpus should add keywords for the reachable ones.
