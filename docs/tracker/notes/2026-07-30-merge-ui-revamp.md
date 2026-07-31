# Merge — teammate UI revamp into local main (not a playbook session)

- **Who:** Anish (resolving), merging vedang-123-ai's 13 commits
- **Date(s):** 2026-07-30
- **Status when I stopped:** merge resolved and committed, all four suites green, **not yet
  looked at on a simulator**

## What happened

`origin/main` and local `main` had diverged: 2 local commits (look-and-feel pass, obstruction
attribution, route-render fix) against 13 remote (R310 egress scoring, then the Jul 27–29 UI
revamp — fixture-kit renderer, glass controls, immersive mode, route-finding views). Common
ancestor `702bea9`.

Only 5 files conflicted; everything else auto-merged, including all of the backend.

| File | Resolution |
|---|---|
| `Renderer/DollhouseScene.swift` | theirs wholesale |
| `Renderer/DollhousePalette.swift` | theirs wholesale (not conflicted — reverted deliberately) |
| `Renderer/RenderOrder.swift` | theirs wholesale (same) |
| `escape_planTests/DollhouseRendererTests.swift` | theirs wholesale (same) |
| `Screens/HouseScreen.swift` | **theirs + local route fix re-applied** |
| `docs/decisions.md`, `activity-log.md` | both sides, chronological |
| `docs/tracker/TODO.md` | union; local completion status wins over their stale copy |

Rationale in decisions.md 2026-07-30.

## Decisions / surprises

**The surprise worth remembering: we both fixed the same bug, each of us only half of it.**
`onRebuild` captures the `HouseScreen` struct once, so every @State read inside it returns
attach-time values. My branch caught it via the routes (routes never drew); their branch
caught it via the explode slider (it snapped back to 0). I boxed the *draw inputs* into
`RouteOverlayHolder`; they boxed the *view state* into `SceneViewStateHolder`. Neither of us
knew the other half existed. A verbatim "take theirs" would have shipped their view-state fix
and silently reverted the route fix — the blocker at the top of TODO.md, back again.

That is the general lesson for this repo: **"take theirs for UI" is a design policy, not a
merge algorithm.** It's correct for anything that renders. It is not correct for a bug fix
that happens to live in a UI file. The tell was that my last commit message named a bug
("Fix escape routes never rendering") — a conflicted file touched by a bug-fix commit needs
reading, not overwriting.

Second, smaller surprise: **their fixture kit derives its whole tone family from
`DollhousePalette.background`** (`basePlate`, `slabSide`, `wallCap`, `openingFrame` are all
`background.blended(with:…)`). My Jul 24 dark-backdrop change wasn't in a conflicted region,
so git had already auto-merged it in — and it would have quietly restyled every fixture they
built. Reverted it to keep their design coherent. The reason I went dark in the first place
(cream reads as a hole against the app's black chrome) is still true and is now an open
design question, not a settled one.

Third: `tools/editorcore/.build` held a module cache keyed to the repo's *old* path
(`~/Documents/congressional_app_challenge`). `swift test` failed with "missing required module
SwiftShims" until `rm -rf tools/editorcore/.build`. Nothing to do with the merge — but the
next person to hit it will think it is.

## Questions for teammates

- **@vedang** — the dollhouse backdrop. Yours is cream (`background` = 0.957/0.937/0.902) and
  the fixture kit's tones all derive from it. I'd switched it to a near-black stage on Jul 24
  because inside the app it butts against black chrome on all four sides and reads as a hole
  in the UI, and because the hot-orange route needs the contrast. I reverted to yours for this
  merge so your fixtures aren't restyled behind your back. Can you look at it on a device and
  decide? If dark wins, the fixture tones need re-deriving, not just the one constant flipped.
- **@vedang** — heads up that `RouteOverlayHolder` now also caches `plan` / `model` /
  `selectedRoomID`. If you touch route drawing: call `applyOverlay()` from fresh-`self`
  contexts only, and `overlayHolder.redraw()` from inside `onRebuild`. Calling `applyOverlay()`
  from `onRebuild` reintroduces the blocker.
- **Anyone** — `.build-assess/` is committed to git. Hundreds of Xcode index `.o` files churn
  on every session and drown `git status`. Should be gitignored + `git rm -r --cached`. I did
  not do it in this merge because it would bury the actual resolution in a 500-file diff.

## Next steps

1. **Boot the merged app on a simulator and look at it.** This is the real gap: all four
   suites pass, but nobody has seen the fixture-kit renderer and the re-applied route fix in
   the same build. Specifically confirm routes still draw after an edit commits (the exact
   thing the fix protects, and the exact thing rebuilds break).
2. Answer the backdrop question above.
3. Then resume the open TODO items — the S3.2 `check_obstructions` agent tool is the largest
   one still unblocked by hardware or keys.
