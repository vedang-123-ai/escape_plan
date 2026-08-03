# Client/server enum tolerance sweep + the Score screen fix

- **Who:** vedang
- **Date(s):** 2026-08-02 (into 08-03)
- **Status when I stopped:** sweep complete, all fixes landed and pushed, iOS unit suite
  309 → 315 green. **The Score screenshot was never captured** — blocked on disk and UI
  automation, not on the code.

## What happened

Started as "show me what the app looks like." Captured the 11 screens with the S44 driver,
looked at them, and found the Score screen dead: *"Couldn't get your score."*

Not a network error — a Swift `DecodingError`. The backend returned 200 with valid JSON.
Chain:

1. The 2026-07-27 R310 work added `category="egress"` in `checklist.py`.
2. Swift's `ChecklistCategory` had no `egress` case.
3. A raw-value enum throws on an unknown string, and that throw propagates to the parent —
   so one unrecognized row failed the entire `ScoreBreakdown`.
4. Broken on `apartment` and `twostory`. `bungalow` never emits `egress`, which is why it
   looked fine to anyone who checked one home.

**It had been broken for six days on the demo home.**

Then the sweep the user asked for: every Swift enum that decodes backend output, diffed
against what the backend can emit. All ten enums' *values* matched — `egress` was the only
live gap. The real finding was the shape of the risk, not a second wrong value.

## Decisions / surprises

**1. The second bug was hiding behind the first, and fixing only the first would have looked
like success.** `ScoreScreen.categoryOrder` is a whitelist. After fixing the decode, `egress`
items would have parsed perfectly and rendered *nowhere* — the R310 egress-window warnings,
the entire point of that session, silently invisible. A green test and a screen that shows
nothing. Now there's a test asserting the whitelist stays exhaustive over the enum.

**2. "Fail loudly on unknown enum values" is not the discipline it sounds like.** The old
`ScoreModelsTests` header said the model was deliberately strict so a backend change "fails
loudly here instead of as a blank Score screen." That is exactly backwards for enum *values*:
a test suite cannot fail on a value that doesn't exist yet. The only thing that ever fails is
the user's app, at runtime, on the demo home. Strict about structure the backend **promised**;
tolerant about values it may later **add**. Rewrote that header.

**3. The sweep's most valuable find wasn't a bug — it was a fuse already lit.**
`RouteFinding.FindingKind` threw on unknown kinds, and findings nest inside `RoutePlan`, so
one unrecognized kind meant **no routes render at all**. Meanwhile `obstructions.py` already
carries `narrows_route` that nothing surfaces yet, and `TODO.md` contemplates surfacing it.
Whoever wired that up would have broken routes outright and had no reason to suspect the
client. Now it degrades, and surfacing `narrows_route` is safe.

**4. Where the sweep deliberately stopped.** The six schema enums (`RoomType`, `OpeningKind`,
`Source`, `ObjectCategory`, `StairKind`, `ProfileTag`) stay strict. They describe the user's
own home, round-trip through local persistence, and are *encoded* as well as decoded — a
silent `unknown → other` fallback would decode a newer build's `"sunroom"` and re-encode it
as `"other"`, degrading the saved home on disk with no error. Data loss dressed as graceful
degradation. Wrote the rationale into `Enums.swift` so nobody "finishes" the sweep later.

**5. `AnalyzeModels` had no test file at all.** Six tests now. Its sibling `ScoreModels` is
where the six-day break lived; the two shipped with the same assumptions and only one had
anyone checking.

## Questions for teammates

- **@Anish / @P1** — the Python suite passed the entire six days this was broken, because it
  never exercises Swift. `/verify` cannot currently tell you the app works. I put a
  suggestion in `TODO.md`: a contract test that imports the backend enums, greps the Swift
  sources, and asserts the value sets match. Cheap, and it would have caught this on day one.
  Worth doing before the demo?
- **@Anish** — `narrows_route` is now safe to surface (`FindingKind` degrades, and
  `RouteFindingViews` has an `.unknown` style). Your call whether it's worth the noise.

## Next steps

1. **Screenshot the fixed Score screen** — the one thing I said I'd deliver and didn't.
   `ScoreScreenshotUITests` is committed but has never completed a run. Needs free disk.
2. The disk on this machine is the real blocker for anything on-simulator: it hit 0 bytes
   mid-session once and 99% twice. ~1.4 GB of the simulator is `MobileAsset`; `minecraft`
   (9.1 GB) and `Autodesk` (8.9 GB) are the big untouched items.
3. Unchanged: `/score`'s un-analysed-home question still needs P1's call, and the dollhouse
   backdrop question still needs a human on a device.
