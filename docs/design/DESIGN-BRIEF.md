# Escape Plan — Design Brief

A paste-ready description of the app as it exists today, for use in Claude Design (or any
design tool) when mocking up new screens or reworking existing ones.

**Read this first:** every colour, size and screen below is what is actually built and shipping,
not an aspiration. Where a rule exists, the reason is given — the reasons are load-bearing and
several were learned the hard way. If a design breaks one, break it deliberately.

---

## 1. What the product is

An iOS app for household disaster readiness. You map your home once — by LiDAR scan, by
importing a floor plan, or by hand in a 3D editor — and the app produces a personalized
readiness checklist plus escape routes computed for each person who lives there.

**Platform:** iOS 17+, iPhone only. Portrait primary. SwiftUI + SceneKit.

**The architectural claim the design must protect:** a deterministic engine computes routes; an
AI layer explains, audits and answers, grounded in a cited FEMA/NFPA/Red Cross corpus. The AI
never computes a route and never invents safety advice. Any design that blurs those two is
wrong — a judge's first question is "isn't this just an AI wrapper?", and the visual separation
is part of the answer.

**Perils in scope:** fire (built), earthquake and severe weather (in progress).

---

## 2. Navigation

Four-tab `TabView`, no nav rail, no drawer.

| Tab | Icon (SF Symbol) | Purpose |
|---|---|---|
| **Home** | `house` | Readiness checklist + preparedness score. The landing surface. |
| **House** | `cube.transparent` | The 3D model. Viewer, editor, route display, fire simulation. |
| **Assistant** | `bubble.left.and.bubble.right` | Grounded chat about your specific home. |
| **Settings** | `gear` | Server connection, about. |

A full-screen onboarding flow covers the tabs on first launch only, then never reappears.
Secondary screens (Score detail, Profiles, Drill, Route steps, Export) are pushed or presented
as sheets from these four.

---

## 3. The colour system — the single most important rule

**Cool hues mean route. Warm hues mean hazard. This holds everywhere, in 3D and in chrome.**

This was learned by breaking it. Routes were originally safety orange, back when a route was the
only coloured thing on screen. Adding the fire simulation put orange routes next to red/orange
hazard — a textbook deuteranopia collision. Routes were re-keyed to cool blue and warm was
reserved for hazard. **Do not put orange on a route, ever.**

Consequence: **app chrome contains no hazard warm and no route cool**, except in legends that
literally label a route, an exit, or the hazard. Advisories use amber (distinguishable from
both). Faults use red. Positive states use the accent green.

### Palette

Every colour is an appearance-aware pair — a light value tuned against `#FFFFFF`/`#F2F2F7` and a
dark value tuned against `#000000`/`#1C1C1E`/`#2C2C2E`. Single values could not survive dark
mode at AA.

| Token | Light | Dark | Use |
|---|---|---|---|
| `accent` | `#0E8A3E` | `#22B45C` | Fills, tints, selection. The app's colour. |
| `accentText` | `#0B7233` | `#34D07A` | Accent-coloured **text** (darkened to clear 4.5:1). |
| `warning` | `#C81E1E` | `#F87171` | Something is broken and you must act. |
| `caution` | `#9A4A08` | `#F59E0B` | Worth noticing, not broken. Amber, deliberately **not** `.orange`. |
| `supporting` | `#6B6B70` | `#AEAEB2` | Quiet supporting text. **Not** iOS `secondaryLabel`, which fails AA at 3.44:1. |
| `routeInk` | `#123FB0` | `#6FA8F5` | Legend swatch for a primary route. |
| `routeSecondaryInk` | `#4180D4` | `#4E97E8` | Legend swatch for a backup route. |
| `exitInk` | `#0F8140` | `#35B265` | Legend swatch for an exit. |
| `hazardInk` | `#C2410C` | `#C2410C` | Legend swatch for fire/hazard. |
| `bubbleUser` | `#1A7F45` | `#1A7F45` | User's chat bubble fill. |

Surfaces: `surface` `#FFFFFF`/`#000000`, `surfaceSecondary` `#F2F2F7`/`#1C1C1E`,
`surfaceTertiary` `#FFFFFF`/`#2C2C2E`.

### Accessibility floor (non-negotiable, unit-tested)

- Body text ≥ **4.5:1**, large text (≥18pt, or ≥14pt bold) ≥ **3:1**, non-text components ≥ **3:1**.
- Minimum tap target **44×44pt**.
- Colour is never the only carrier of meaning — routes differ by dash pattern and numbered stops,
  not just hue, so the plan reads in greyscale and for colour-blind users.
- Every animation needs a Reduce Motion path. The fire simulation, for example, steps forward in
  one-second jumps instead of animating continuously.

---

## 4. Typography

Semantic scale, all built on system fonts and Dynamic Type:

| Token | Definition | Use |
|---|---|---|
| `screenTitle` | `.title2` semibold | Heading inside a scroll view (not the nav title). |
| `sectionHeader` | `.subheadline` semibold | Label above a group. Rendered **uppercase, 0.6 kerning, in `supporting`**. |
| `metric` | `.largeTitle` rounded bold | The one number a screen exists to show (the score). |
| `cardBody` | `.callout` | Body copy in a card. |
| `detail` | `.caption` | Captions, footnotes, banner text. |

---

## 5. Voice

Plain, calm, second person. This is a safety app for families, not a pro tool.

- "Let's map your home", "Start a fire in one room and the engine re-plans everyone's way out."
- Never alarmist. Never jargon. Findings say what's wrong *and what it means*.
- Failures are honest and specific: "AI features are unavailable right now" plus what still
  works, rather than a generic error. A failure that can't be retried gets **no Retry button**.

---

## 6. Screens

### 6.1 Home — readiness checklist
Nav title: the active home's name, else "Readiness".

- **Score card** (tappable → Score detail): "Preparedness Score", big number, "Tap for full breakdown".
- **Checklist sections** in fixed order: `CRITICAL` (in `warning`) → **Foundation** (smoke alarms)
  → **Know your home** (routes, AI findings) → **Practice**.
- **Menu** (`ellipsis.circle`): Scan New Home (`camera.viewfinder`), Build Manually (`plus`),
  Import Plan (`wand.and.stars`), and a list of saved Homes.
- **Empty state:** `house` icon, "Let's map your home", body copy, "Scan My Home" primary +
  "Build It Myself" secondary.
- **States:** scoring spinner; "Score unavailable" with a Retry.

### 6.2 House — the 3D model (the centrepiece)
Nav title: the home's name. This is one screen doing four jobs at once: viewer, editor, route
display, and fire simulation.

**Layout:** a rounded-corner **card** (26pt continuous corners, soft shadow, inset) holding the
3D scene, above a **fixed-height 240pt dock** that scrolls.

- **Floating glass controls** on the model's top edge: floor chips (one per storey), a spotlight
  toggle, and a fullscreen expand. Liquid Glass on iOS 26+, `.regularMaterial` below.
- **Fullscreen mode** hides the dock, nav bar, tab bar and status bar; the explode slider floats
  in glass at the bottom so it isn't lost with the dock.
- **Dock sections**, in order: `Escape routes` (person picker: "Everyone" or a named profile) →
  `Route check` (findings, count badge) → `Fire simulation` → `Simulation check`.
- **Sheets:** Route steps (numbered, matching the numbers on the model), room picker for
  ignition, add stairs.

**The 3D style — "White Model".** A monochrome architectural maquette, deliberately:
opaque shadow-casting white walls, SSAO, a chamfered plinth with a soft contact shadow, ghost
outlines for inactive floors. Doors stand ajar (reads as a door in monochrome, and the swing
communicates circulation). Windows read by a bright frame and a glint, not a blue tint.
**Rooms are not colour-tinted** — they're separated by walls and named by labels.

The reason is the colour rule: the model is white so that **the only saturated colour in the
frame is a route, an exit, or a hazard.** Any design that adds decorative colour to the model
breaks the app's most important signal.

**Fire simulation:** pick a room, ignite it, and the engine re-plans around the spreading
hazard. Playback with replay, speed control, and a timeline scrubber. Nothing about the saved
plan changes.

### 6.3 Assistant — grounded chat
Nav title "Assistant". New Chat button (`square.and.pencil`).

- "Grounded in {home name}" banner with a `house` icon — the AI answers about *your* home.
- Empty state: "Ask about your escape plan".
- User bubbles in `bubbleUser` green; assistant replies carry **citation chips** on
  `surfaceTertiary`.
- Typing indicator. Errors are inline with a Retry where retrying can help.

### 6.4 Score — preparedness detail
Big `metric` number "of 100", then a per-component breakdown with earned/max points and a
rationale line each, plus a "How it's scored" disclosure. A stale-score banner appears if the
figure may be out of date.

### 6.5 Profiles
The people and pets who live here, so routes can be personalized (a mobility-limited upstairs
sleeper is exactly the case the engine exists to catch). Empty state: `person.2`, "No profiles
yet". Swipe to delete with confirmation.

### 6.6 Settings
Sections: **Server** (connection status, Test connection) → **Advanced** (server address,
access token, Save changes) → **Developer**, debug builds only (Use deployed server / Use local
dev server) → **About**.

### 6.7 Other surfaces
**Drill mode** (practice log, cited reminders, honest time-to-exit), **Export** (one-page-per-floor
PDF, legible in greyscale), **Onboarding** (seeds a demo home, forces review of low-confidence
scan items, lands on routes).

---

## 7. Component patterns

- **Findings** are cards with a severity style: icon, title, the room it applies to, and what it
  means. An all-clear state reads "No issues flagged for this view" — never an empty void.
- **Empty states** use `ContentUnavailableView`: icon, title, one sentence of body, one primary
  action, optional secondary.
- **Failures** route through one classifier and one banner component. Retry appears only when
  retrying could work.
- **Section headers** are uppercase, kerned, in `supporting`.
- Cards are used only where elevation means something. Rooms in the model are separated by
  geometry, not by tinted patches — the same restraint applies in chrome.

---

## 8. If you are redesigning, keep these

1. Cool = route, warm = hazard. Everywhere.
2. The 3D model stays white so route/exit/hazard are the only saturated things on screen.
3. Contrast floors are unit-tested; a design that fails them will fail CI.
4. Colour is never the sole signal — dashes and numbers carry the plan in greyscale.
5. Failure copy stays specific and honest; no Retry on an unretryable failure.
6. The deterministic engine and the AI stay visibly distinct.

## 9. Known weak points — good places to design

- The House dock is dense: four sections in 240pt, and the fire simulation competes with routes
  for the same space.
- Onboarding is functional but plain — it's the judge's first thirty seconds.
- The checklist's four fixed categories may not scale to three perils.
- No tablet layout; iPhone portrait only.
- Camera feel has never been tuned on physical hardware.
