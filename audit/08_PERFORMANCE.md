# 08 · Performance

Canonical home for AUD-047. Only bottlenecks with measurements or strong code evidence are listed; the 2026-09-25
audit's "parallelise `/score` with asyncio" was rejected with measurements (`docs/decisions.md`) and is not re-opened.

## Measurements taken in this audit (2026-09-28)

| What | Result | How |
|---|---|---|
| Deployed `GET /health`, cold | **51.2 s** | `curl -w %{time_total}` |
| `compute_route_plan(twostory, fire)` locally, ×1 / ×4 / ×10 linear scale | 0.07 s / 1.15 s / 7.24 s | scratch script `bigroom.py` |
| Argon2 `verify_password` locally | 36.5 ms | 5-iteration average |
| Backend test suite | 29.7 s for 893 tests | pytest |
| EditorCore | 614 tests in 4.8 s | `swift test` |

## Findings

| ID | Severity | Summary | Canonical file |
|---|---|---|---|
| AUD-004 | P1 | Route cost ∝ floor area (10 cm pure-Python grid), no bounds; `/score` runs it 3× | 06 |
| AUD-005 | P1 | Argon2 on the event loop | 06 |
| AUD-035 | P2 | No AI timeouts; builder re-sends the image each iteration; chat history unbounded | 03 |
| AUD-032 | P2 | Cold start (51 s) vs 60 s chat timeout | 05 |
| AUD-047 | P3 | Library listing decodes every home on the main thread | below |

---

### [AUD-047] `HomeDocumentStore.list()` fully reads and decodes every home file on the main thread (known)

**Severity:** P3
**Location:** `escape_plan/Persistence/HomeDocumentStore.swift:74-100`, called from `HomeLibrary.refresh()`
(`HomeLibrary.swift:50-52`) — at init, after every delete/duplicate, after onboarding, after every sync with pulls,
and after **every autosave in the "Build Manually" editor** (`HomeScreen.swift:122-126` passes `library.refresh()` as
`onModelChanged`).
**Category:** performance
**What I found:** `list()` does `Data(contentsOf:)` + `HomeDocument(data:)` (a full JSON parse into `JSONValue`) for
every file, synchronously, on `@MainActor`.
**Current behavior:** Fine for the typical 3–6 homes. It scales with the number and size of homes, and homes are never
deleted (AUD-021), conflict copies accumulate (AUD-015), and every drag in the new-home editor triggers a full re-list.
**Expected behavior:** Read summaries off the main actor, or keep a small index (name, counts, modified) updated on save.
**Evidence:** Code reading; already on the BLOCKERS "Deferred on purpose" list ("Move `HomeDocumentStore.list()` off
the main thread"). Not measured on a device.
**Potential fix direction:** `Task.detached` for the read + `@MainActor` assignment; or decode only `home_id`, `name`,
`meta.modified` with a lightweight `Decodable`.

## Not findings (checked)

- `HouseScreen` builds a new `HomeDocumentStore` (a `createDirectory` syscall) on each struct init (AUD-019) — cheap, but
  it happens on SwiftUI re-evaluation; fix with AUD-019.
- The iOS app issues one `/score` per toggle (cancelling the previous) — acceptable; the cancellation UX is AUD-014.
- No polling loops were found; sync runs on launch, sign-in and foreground only.
