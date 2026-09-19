# 2026-09-14 · Review of the pulled S9 code, and the doc drift it exposed

Read-only review session. No Swift was changed. **No simulator was used** — the owner's
standing restriction was hardened this session from "ask first" to "don't".

## What I could and could not verify

`xcrun swiftc -parse` is parse-only and needs no simulator or SDK resolution. All seven
new Swift files parse clean. **That is syntax, not type-checking** — it does not mean
they compile.

`notes/2026-09-14-S9.2-UI-Setup.md` claims "Verified fixes with `xcodebuild test`
successfully". That is plausible (presumably the author's machine) but carries no count
and no result bundle, which this repo's own rule requires because the unit target prints
`Executed 16 tests` under Swift Testing. **S9.3's note claims no test run at all**, and
S9.2/S9.3 added 481 lines after that claim. I had earlier written in `BLOCKERS.md` that
the S9 Swift had never been compiled; that overstated what is known, and the line is
corrected.

## Anish's three S9.1 fixes are real — I checked the code, not the claim

| Claimed | Verdict |
| --- | --- |
| AABB area → projection onto the longest wall's axes | Real. `extractedBoundingBox` projects wall endpoints; the model side uses Shoelace. |
| `rotationY` → right-handed, call site `+ang` | Real. Matrix is `[c,0,s],[0,1,0],[-s,0,c]`; call site passes `ang`. |
| No-door ambiguity via an evaluation tally | Real. `roomEvaluationCounts` fires when one room matches at both 0° and 180°. |

## What review found on top (all in BLOCKERS §3)

1. **Every AR waypoint is pinned to 1.0 m with no floor term** (`ARDrillView.swift:68`).
   On `twostory.json` a route spanning both levels draws at one height. Multi-floor is in
   scope and stairs are modelled, so this is not an edge case.
2. **A room with no doors scores a perfect 0** and outranks correctly-matched rooms —
   absence of evidence scored as perfect evidence. The correct room can be pushed out of
   the candidate list, leaving the user disambiguating among wrong answers only.
3. **RoomPlan wall-splitting** remains unfixed; Anish's own audit raised it and the S9.2
   audit confirms it was deliberately deferred. Everything keys off the longest wall, so
   the failure is silent and total.
4. The S9.3 note says it "replaced `DrillSession` completely". **It did not** —
   `DrillSession` still exists and `DrillScreen` uses it at four sites. The AR path was
   added alongside. Safer than the note implies, but the note is wrong.

## Doc drift fixed

`README.md`'s Scope section was stale in four places, **three predating this session**:
furniture detection listed as out (reversed 2026-09-08), no-accounts and multi-user sync
listed as out (reversed 2026-09-14), and a claim that no S6 session had been built
(S6.1–S6.9 are done). Replaced with a table of the three approved widenings so the next
reversal has an obvious place to land.

## Green

Backend 442 not-live, EditorCore 295, corpus 24/9/2. iOS not run and not runnable here.
