# Simulator pass on the merged build (not a playbook session)

- **Who:** vedang
- **Date(s):** 2026-08-02
- **Status when I stopped:** merge verified on the simulator. Routes draw and survive a
  committed edit. Regression guard committed. Backend and simulator shut down.

## What happened

Closed the #1 next step from Anish's 2026-07-30 merge note: "boot the merged app on a
simulator and look at it." Four suites had been green since the merge, but nobody had seen the
fixture-kit renderer and the re-applied route fix in the same build — and those two came from
different branches that had each fixed *half* of the same stale-`@State` bug.

- Built, booted, installed, ran the existing S44 screenshot driver against a local backend
  (`BACKEND_BEARER_TOKEN=devtoken`, `uvicorn` on :8000) — 11 screens captured.
- Wrote `escape_planUITests/RouteRedrawAfterEditUITests` and ran it: routes drawn → **Add
  Object** commits → routes redraw. Passed.
- Curated evidence: `docs/evidence/route-redraw-2026-08-02/`.

Verdict: the merge is sound. Orange primaries, blue dashed secondaries on the per-room view,
green exit glows, fixture-kit doors and windows, profile switching — all working together.

## Decisions / surprises

**The assertion had to be pixels, not controls.** The obvious test is "after the edit, do the
route controls come back?" That test passes on the *broken* build — the bug's signature was
literally "controls appear but no route draws." So the test rasterizes the screenshot and
counts route-orange pixels in the 3D view, before and after. It's a cruder assertion than I'd
normally write, and it's the only one that actually distinguishes the two states.

**The accident worth keeping.** The object the test adds to force a commit landed in front of
a doorway. So `after-edit.png` incidentally shows the whole obstruction chain working end to
end in the UI — two red `!` markers, a `Route check 3` badge, and the measured "there is no
path to that doorway at all. Moving it…" advice from `obstructions.py`. I went looking for a
route redraw and got the first captured proof that the obstruction attribution reaches a
user-visible surface. Left the test as-is rather than moving the object somewhere harmless:
the stronger edit exercises more of the rebuild path.

**`TEST_RUNNER_*` must be in xcodebuild's environment, not passed as build settings.** I lost
a 64-second run to `TEST_RUNNER_S44_SHOTS=1` sitting at the end of the `xcodebuild` argument
list, where it is silently ignored and the driver just skips. `export` it instead. The skip
reason is only visible via `xcrun xcresulttool get test-results tests --path <xcresult>` —
the console output says nothing but "1 test skipped."

**Disk space is a live hazard on this machine.** The session hard-stopped mid-pass at 0 bytes
free — every tool call fails once `/tmp` can't be written. vedang freed ~5 GB; the rebuild took
1.2 GB and the two test runs took another 1.6 GB in derived data and `.xcresult` bundles,
ending at 2.4 GB free. `.build-merge/Logs/Test/` accumulates an xcresult bundle per run and
nothing prunes it. Related and still open: `.build-assess/` is committed to git.

## Questions for teammates

- **@Anish** — your merge holds up; I couldn't find a seam. The one thing I did not verify is
  the thing you actually asked about: the **backdrop question** is still open, and I
  deliberately didn't touch it. Looking at the captures, the cream stage reads fine in
  isolation but the 3D view is a bright panel floating in dark chrome, which is the effect you
  described. It needs your eye and vedang's on a device, not mine on a screenshot.
- **@Anish** — `RouteRedrawAfterEditUITests` is env-gated and needs a local backend, so it
  won't run in a normal `/verify`. If we want it to actually catch a regression, it has to go
  somewhere that runs it. Worth a line in the verify-all skill?

## Next steps

1. The backdrop decision (above) — blocked on a human looking at a device.
2. `/score`'s un-analysed-home question still needs P1's call. Unchanged, and still the
   largest open non-hardware item.
3. Housekeeping that is now overdue: gitignore + `git rm -r --cached .build-assess/`, and
   prune `.build-merge/Logs/Test/`. This machine has ~2.4 GB free.
