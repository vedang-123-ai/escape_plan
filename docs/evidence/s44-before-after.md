# S4.4 polish pass — before / after

Captured on the iPhone 17 simulator (iOS 26.5) with the three fixture homes seeded
(Bungalow, Apartment 4B, Two-Story House) and the backend running locally. Both sets were
produced by the same unattended driver (`escape_planUITests/S44ScreenshotUITests`, run with
`TEST_RUNNER_S44_SHOTS=1` and `TEST_RUNNER_S44_OUT=<dir>`), so the framing is identical.
The `offline-*.png` shots come from `S44BackendDownUITests` (`TEST_RUNNER_S44_DOWN=1`) — the
app pointed at a dead port, demonstrating S4.3's graceful-degradation bar.

| Screen | Before | After | What changed |
|---|---|---|---|
| Onboarding welcome | `s44-before/01-onboarding-welcome.png` | `s44-after/01-onboarding-welcome.png` | Hero mark (house + runner in tinted circle), warmer copy ("Map your home, and every room gets a way out"), ember accent |
| Home library | `s44-before/02-home.png` | `s44-after/02-home.png` | Ember accent; empty state (not shown) now leads with "Scan My Home" |
| Plan — whole house | `s44-before/03-plan-everyone.png` | `s44-after/03-plan-everyone.png` | **The headline fix**: warm architectural-model palette, exterior vs interior walls, soft shadows — and the primary routes are actually *visible* (x-ray rendering; before, wall alpha stacked until the tubes vanished) |
| Plan — Bungalow / Apartment | — | `s44-after/03b-plan-bungalow.png`, `03c-plan-apartment.png` | Same treatment holds on the other two fixtures |
| Plan — room routes | `s44-before/04-plan-room.png` | `s44-after/04-plan-room.png` | Primary thick + pulsing with start marker, secondary dashed blue, both readable through walls |
| Plan — camera tour | `s44-before/05-plan-midtour.png` | `s44-after/05-plan-midtour.png` | Before: a blank gray wall. After: the glowing route ahead, eased flight, 65° lens, room labels hidden mid-tour |
| Plan — profile switch | `s44-before/06-plan-profile-maya.png` | `s44-after/06-plan-profile-maya.png` | Maya's route from the kids' bedroom, same renderer gains |
| Editor (view only) | `s44-before/07-editor.png` | `s44-after/07-editor.png` | Editor untouched (Lane A owns it) — palette continuity comes free via the shared scene builder |
| Assistant — empty | `s44-before/08-chat-empty.png` | `s44-after/08-chat-empty.png` | Warmer empty-state copy; messages animate in |
| Assistant — reply/error | `s44-before/09-chat-reply.png` | `s44-after/09-chat-reply.png` | Plain-language error copy, warning haptic; before-shot also shows the stale-thread duplication the driver now avoids |
| Settings | `s44-before/10-settings.png` | `s44-after/10-settings.png` | Connection status light, "server address"/"access token" language, deployed-URL default, DEBUG server switcher |
| Score | `s44-before/11-score.png` | `s44-after/11-score.png` | Animated score ring replaces the bare number; friendlier error/retry |
| Profiles | `s44-before/12-profiles.png` | `s44-after/12-profiles.png` | Accent + copy only — structure was already right |
| Drill — picker | `s44-before/13-drill.png` | `s44-after/13-drill.png` | Readable tag labels, haptics on start/step/practiced |
| Offline (backend dead) | — | `s44-after/offline-01-plan.png`, `offline-02-chat.png`, `offline-03-score.png` | Cached-routes banner / chat Retry / score Try Again — zero crashes with the server gone |
