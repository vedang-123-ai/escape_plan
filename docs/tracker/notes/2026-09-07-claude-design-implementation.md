# Claude Design implementation — restyle of Home/Assistant/Settings/Onboarding/Score, Beta tab, design export

- **Who:** Claude session with Yuki (owner-directed, outside the S-numbered arc)
- **Date(s):** 2026-09-07
- **Status when I stopped:** build green (all restyled screens + `DesignKit` + Beta tab + House
  dock switch); Home, Assistant and Settings verified in the simulator against the **local**
  backend on schema 2.0; House, Score, Beta and all four onboarding steps checked too;
  unit suite green (485/0). See "Verification" below. **Nothing
  is committed** — the owner's earlier commit request was interrupted and not re-issued.

## What happened

- **Design source.** Claude Design project `66734cd4-4e07-4cf5-a116-5ded7e6dec0c`
  (`Escape Plan.dc.html`, plus `ios-frame.jsx` / `support.js` it imports). The `claude_design`
  MCP could not be authorised in this session (`/design-login` unavailable), so the files were
  pulled through the owner's signed-in browser pane via the page's own
  `OmeletteService/GetFile` RPC and transcribed into `docs/design/claude-design-export/`
  (README there has the provenance table and the re-fetch recipe).
- **New `Screens/DesignKit.swift`** — the design's tokens (page gradient, ink/bodyInk/supporting,
  card/inset/track fills, radii, `pagePadding`, shadow) and components (`dsPage()`, `dsCard()`,
  `DSPill`, `DSPrimaryButton`, `DSSecondaryButton`, `DSPressStyle`, `DSIconBadge`). Everything
  colour-critical still routes through `Theme` so the WCAG rule (cool = route, warm = hazard;
  chrome never borrows either) is unchanged.
- **Restyled screens (behaviour unchanged, layout per the design):**
  - `HomeScreen` — 240° score gauge ("Tap for breakdown" → Score), readiness card with next
    milestone bar, 2×2 stat tiles (alarms / routes / findings / drills) with Done/To-do chips,
    critical-finding cards ("Show me where" / "Why it matters"), the S6.6 per-item checklist
    kept below the tiles, floating "Run a fire drill" CTA. Inline title.
  - `AssistantScreen` — sparkles badge header, radial glow empty state with four suggestion
    pills, capsule composer, restyled bubbles + citation chips. The "The AI explains your plan…"
    footnote is gone (owner's instruction in the design chat).
  - `SettingsScreen` — large title, grouped white cards with 60pt rows; About row →
    `HowRoutesAreComputedSheet`. Footnote corrected to say the engine computes routes and the
    assistant explains them.
  - `OnboardingFlowView` — step dots, hero mark, 28pt titles, card-wrapped fields, 56pt primary
    + "I'll do this later". Still writes the same `OnboardingState`.
  - `ScoreScreen` — 72pt number, per-component tinted bars, "Why" disclosures; ring removed.
  - `HouseScreen` dock — `DockMode` switch (Routes / Fire) replaces the stacked controls; page
    gradient behind the model card. The 3D SceneKit house is untouched.
- **Beta tab** (`Screens/BetaScreen.swift`, leftmost in `ContentView`) — the pre-S6 homes library
  (fixtures, thumbnails, swipe → Score/Profiles/Drill, long-press → printable plan, scan/build
  entry points), recovered from commit `3babbc0`'s `HomeScreen`. Kept because the owner tests
  against those houses; labelled as a test surface in its footer.
- **The house stays 3D.** The design draws a 2D SVG house; it was not ported. It is retrievable
  in the export (`docs/design/claude-design-export/Escape Plan.dc.html`, `<svg data-house>`).
- **Two stale backends, one misleading card.** Home showed "Score unavailable — the server
  couldn't use what we sent" (422). Cause: the local uvicorn had been started before the
  schema-2.0 commits and runs without `--reload`; restarted → `/score` 200. Separately, the
  deployed Render backend is *also* pre-2.0 (422 for the same reason) and cold-starts in ~32 s,
  which the app reports as "couldn't reach the server". Neither is a UI bug.

## Decisions / surprises

Promoted to `docs/decisions.md` (2026-09-07 ×4): restyle-not-rewrite with the named deviations;
Beta tab placement; export method + omitted runtime shim; the stale-backend lesson.

Surprises worth knowing:
- `simctl list devices available` lists five iPhone 17 Pro devices but only the iOS 26.5 one has
  an installed runtime — `xcodebuild` rejects the others as destinations. Tests therefore run on
  the same simulator the app is being inspected on, and relaunch it.
- The design's `ios-frame.jsx` came out byte-exact (16,507 B); the `.dc.html` differs from the
  server copy only by the injected `data-omelette-injected` shim (documented in its head comment).

## Questions for teammates

- @owner: should the Beta tab ship in Release builds? It is visible in all configurations right
  now, as asked. Wrapping it in `#if DEBUG` before the Oct 24 submission is a one-line change.
- @owner: the Render backend needs a redeploy from `main` (schema 2.0) or every fresh install
  sees "Score unavailable" on first launch.

## Verification

- Build: `xcodebuild` green (simulator build via the iOS Simulator MCP), no new warnings noted.
- Simulator, local backend on current `main`: Home gauge 72 / "Nearly ready" / tiles / CTA ✔;
  Assistant empty state ✔; Settings cards + Developer switches ✔.
- House dock: Routes mode (section header, person picker, route steps) ✔; Fire mode (lede,
  disabled Ignite until a room is picked, room picker) ✔; 3D model card + glass floor chips ✔.
- Home gauge → Score push ✔ (verified from a scrolled-to-top state). Score: 72-pt number, band
  label, tinted breakdown bars, "Why" disclosures ✔.
- Beta tab: five saved test homes with thumbnails, footer copy ✔.
- Onboarding (flag reset in the **app-container** plist — `simctl spawn … defaults write
  cac.Escape-Plan` writes the wrong domain): welcome, who-lives-here, needs, rent/own ✔. Walked
  with Continue and then exited by restoring the flag by hand, so `commitAndFinish` never wrote
  interview data into the owner's test home.
- **Observed once, not reproduced:** after a House push/pop from Home, the Home ScrollView was
  sitting ~1500pt down without any scroll input, and a blind tap then hit a stat tile instead
  of the gauge. A deliberate tab-away/tab-back did not move the offset, and `fetchScore` keeps
  `breakdown` during a re-score, so there is no obvious reflow. Worth one eye on the device pass.
- Unit tests (`-only-testing:escape_planTests`, iPhone 17 Pro iOS 26.5, `.build-assess`):
  **485 executed, 0 failures — TEST SUCCEEDED.** UI tests not run this session (TODO).

## Next steps

1. Finish the verification list above; run `-only-testing:escape_planTests` and fix anything the
   restyle broke (accessibility identifiers were preserved on purpose — check the UI tests too
   before merging).
2. Deferred design items (tracked in TODO): collapsing House model card (400→190pt on scroll),
   House title-row Export/Edit pills, `DSPill` person picker (kept native `Picker` to preserve
   `plan.profile.picker` a11y ids).
3. Rebase onto `main` (another session commits there) before any commit; do not commit until
   the owner asks again.

---

## Second pass (same day): haptics, gauge sweep, compact checklist, House collapse, composer

Owner asked for five things after the first pass; all landed and built green.

- **Haptics on every interaction.** `Support/Haptics.swift` grew a vocabulary (`press`,
  `selection`, `tick`, `begin`, `hold`, `swipe`, `success`/`warning`/`error`) plus
  `HapticSweep`, a prepared generator for rapid notch runs. Buttons get the click from their
  styles — `DSPressStyle`, the new `HapticPlainButtonStyle` (replaces `.plain` on rows, tiles,
  dock controls), `GlassChipButtonStyle`, and `.hapticTap()` for system styles (`.bordered`,
  toolbar Done buttons). Value-driven surfaces call the funnel: tab switch (`ContentView` now
  owns the selection), pickers and toggles (`selection`), pull-to-refresh (`begin`), Beta swipe
  actions (`swipe`; delete = `warning`), Score's "Why" disclosure, the House dock seating into
  collapsed/expanded. Side effect worth knowing: the app now **lands on Home**, not Beta.
- **Score gauge sweep.** `DSScoreGauge` counts up from 0 (or from the previous score) over
  0.9–1.4 s with ease-out; arc, 25 notches and the number move together, one light impact per
  notch with rising intensity, a medium stop, and the success notification at 85+. Reduce Motion
  shows the value at once with a single tick. Runs on first score and on score change only —
  not on every tab return.
- **Compact checklist.** Rows are title + hazard chip + chevron. Tapping a row opens
  `ChecklistItemSheet` (medium/large detents): status/hazard/category chips, title, full detail,
  source citation, and one primary action that mirrors the old row tap (Show me where / Run a
  drill / Mark as done). Narrative items keep a one-tap checkbox on the left. A header above the
  first group shows "N of M to do" and a **Show details / Hide details** pill that reveals every
  detail line inline (persisted via `@AppStorage("home.checklist.showDetails")`).
- **House card collapse (design 1a).** The card is 400pt at rest and shrinks 1:1 with the
  dock's scroll offset down to 190pt; a leading spacer in the dock takes the height back so
  content tracks the finger, and a trailing spacer equal to the collapse range guarantees enough
  scroll room even when the dock barely overflows. Status banners fade out as it collapses; the
  illustrative notice stays. Offset comes from `onScrollGeometryChange` on iOS 18+; the classic
  GeometryReader-preference pattern is kept only as the iOS 17 fallback because **on iOS 26 it
  fired at initial layout and never again while scrolling** (verified with a debug log, since
  removed). SceneKit rescales the model to the shorter view (vertical FOV), which is exactly the
  design's "meet" scaling; the only frame changes are user-driven scrolls, never mid-drag.
- **Assistant composer.** Moved into the message list's bottom `safeAreaInset` (the canonical
  keyboard-avoiding placement), `.scrollDismissesKeyboard(.interactively)`, tap-on-list
  dismisses, focus scrolls the newest message into view, `.submitLabel(.send)`.
- **Also:** `fetchScore` no longer wraps the checklist swap in `withAnimation` — animating a
  wholesale content replacement is the one plausible cause of the scroll-offset reset seen twice
  in the first pass; three toggle/refresh cycles afterwards held position.

### Verification (simulator, local backend)

- Home: gauge lands on the score; compact rows; header + Show/Hide details ✔; row → sheet ✔;
  "Mark as done" flips pill/button/row in place ✔ (then restored to leave the demo data as
  found); no scroll jump across three refreshes ✔.
- House: rest 400pt → collapsed 190pt with the dollhouse rescaled, dock content 1:1 ✔.
- Assistant: field focuses, typed text lands, send arms ✔. **Not photographed with the on-screen
  keyboard:** this Simulator session keeps Mac-keyboard passthrough on regardless of the
  `ConnectHardwareKeyboard` preferences (global and per-device, both tried with Simulator.app
  restarts; prefs reverted). ⌘K in Simulator, or a device run, will show the composer riding the
  keyboard — that is what the safe-area-inset placement exists for.
- Haptics cannot be felt in the simulator; call sites were verified by reading, not by hand.
- **Side effect found and cleaned up:** the onboarding verification's "Get started" seeded a
  duplicate "Demo Home (scanned)" (4:40 PM), and a second one appeared during the earlier unit
  test run (4:43 PM). Both deleted from the Beta list; the July 29 original stays. TODO has the
  root cause (seeding is not conditional on an empty library).
  Second run of the unit suite confirmed it: a new home file appeared in the container at the
  suite's start time. Removed; TODO names the test-hygiene fix.
