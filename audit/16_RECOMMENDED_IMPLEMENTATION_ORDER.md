# 16 · Recommended Implementation Order

Ordered by dependency and risk, sized for the calendar in `CLAUDE.md` (end-to-end demo path by **Oct 5**, submit by
**Oct 24, 2026**). Each phase lists why it comes where it does. Follow the repo's own protocol for every phase: one
branch per unit of work, touch only the files named, run the gate, merge `--no-ff`, push, update `BLOCKERS.md`, write a
note.

## Phase 0 — Unblock and stabilise the baseline (hours; mostly owner)

| Do | IDs | Why first |
|---|---|---|
| Push `drill-3d-fallback`, merge to `main` after the gate | AUD-034 | Every later branch should start from a `main` that has a working drill |
| Owner: fix the deployed token; top up Anthropic (or decide to demo without AI) | AUD-001, AUD-002 | Nothing on the demo path can be verified end-to-end until these are true |
| Fix the 4 test-side causes of the red iOS suite (ad-hoc signing for Keychain tests, apartment expectation → 2, force `-auth.gate.dismissed NO`, scroll to the Settings disclosure) | AUD-036 | A green baseline is what makes every later regression visible |
| Apply the tracker corrections | AUD-048 | So the next session's first read (BLOCKERS) is true |

**Depends on nothing. Everything else depends on it.**

## Phase 1 — Safety and truthfulness of what the app says (1 short session)

| Do | IDs | Why here |
|---|---|---|
| Delete the client-authored tornado sentence; render engine findings verbatim; add a test | AUD-025 | Directly contradicts the product's core promise and could mislead in a real event; a two-line fix |
| Rewrite the privacy copy and its pinning tests | AUD-050 | Judges and App Review check it; copy-only |
| Stop scoring AI drafts; open the editor after `/build` | AUD-023 | Restores the scope-lock guarantee; small, contained in `ReadinessStore` + `HomeScreen` |
| Decide on `/analyze` + `/explain`: re-wire or re-word the pitch | AUD-022 | A product decision that shapes Phase 3 and the script (S11.12) |

**Why before data integrity:** these are cheap, and each is a claim a judge can test in minutes.

## Phase 2 — Data integrity and core user flows (1–2 sessions, iOS)

| Do | IDs | Why here |
|---|---|---|
| Give each home one owner or a reload-on-change check in House; re-arm sync guard on appear | AUD-013 (+ AUD-017, AUD-019) | Silent loss of edits; must land before new writers (Profiles, delete) are re-wired, or they inherit the bug |
| Re-wire Profiles from Home and the drill's empty state | AUD-020 | Unblocks the drill for users' own homes — the core readiness action |
| Home delete / duplicate in the switcher; don't persist a blank home until first edit | AUD-021 (+ AUD-039) | Needs AUD-013's single-writer rule so deleting an open home is safe; unblocks cleanup of conflict copies |
| Guard `ReadinessStore` against late responses; ignore `URLError.cancelled` | AUD-014 (+ AUD-046) | Small; same files as AUD-023 |
| Fix sync ordering (check the editor guard before preserving a copy) | AUD-015 | Depends on AUD-013's new `openHomeID` semantics |

**Dependency chain:** AUD-013 → (AUD-020, AUD-021, AUD-015). Do AUD-013 first even though AUD-020 is more visible.

## Phase 3 — Backend hardening (1 session, backend; parallel with Phase 2)

| Do | IDs | Why here |
|---|---|---|
| Geometry/size bounds + body-size limit | AUD-004 | Needs a decision on schema bump vs server-only limits (`schema-contract-guardian`) |
| Thread-offload Argon2; throttle `/auth/*`; wire `needs_rehash` | AUD-005, AUD-011 | Independent of iOS |
| Global daily AI budget; key limiter on the trusted XFF hop; guard `/score` recommendations; client timeouts/deadlines; input caps | AUD-003, AUD-006, AUD-035 | Must precede any AI top-up that is publicised |
| `/homes` quotas; `base_revision` compare-and-set | AUD-007, AUD-016 | The 409 path needs an iOS change — pair with Phase 2's sync work |
| Narrow `/convert`'s except; shared `require_token` | AUD-010, AUD-043 | Trivial, same files |

**Why parallel:** backend files do not overlap the iOS files in Phase 2 (lane separation per the playbook).

## Phase 4 — API/client integration correctness (1 session)

| Do | IDs | Why here |
|---|---|---|
| Transcode + resize photos to JPEG; server media-type allow-list | AUD-024 | Needs Phase 3's input caps on `BuildRequest`; verify live once AUD-002 is fixed |
| Recurrence end to end (timestamps + `now`), plus a decision on existing `true` values | AUD-026 | Touches `ScoreRequest` contract and iOS storage; do after Phase 2 stabilises `ReadinessStore` |
| Route cache keyed by peril/profile/fingerprint | AUD-028 | Independent |
| Chat timeout ≥ 120 s; distinct "server waking up" failure | AUD-032 | Small; pairs with AUD-046 |
| Re-check failure label and retry | AUD-029 | Small, `HomeScreen` only |
| Settings snapshot → active home, visible errors | AUD-027 | Small |

## Phase 5 — Reliability and privacy of storage (1 session)

| Do | IDs | Why here |
|---|---|---|
| File sharing off in Release; move internal stores to Application Support with migration; scan cleanup | AUD-008 (+ AUD-012) | A storage move is risky — only after Phase 2's single-owner store exists, and with a migration test |
| Token/URL settings: override flag, validation, hide Advanced in Release | AUD-009 | After AUD-001's rotation decision |
| Refresh tokens or longer TTL + "sign in again" prompt | AUD-031 | Optional feature; after core flows |
| Retry index creation | AUD-042 | Trivial |

## Phase 6 — Grounding depth and CI (1 session)

| Do | IDs | Why here |
|---|---|---|
| Uncited-claim check or structured chat output | AUD-030 | Needs a funded key to evaluate (AUD-002) and the cost caps (AUD-035) |
| Nightly `ios-tests`; Render deploy after checks pass | AUD-037 | Only useful once Phase 0 made the suite green |
| Per-home conversation files, history cap | AUD-033 | Low risk |
| Sync disclosure line about device-only progress | AUD-018 | Copy-only; pair with AUD-050 follow-ups |

## Phase 7 — Cleanup and polish (anytime after Phase 2)

AUD-038 (owner confirms tool disclosure — **do before submission regardless**), AUD-040 (delete scratch files),
AUD-041 (3.12 venv, dev requirements), AUD-044 (dead code), AUD-047 (list off main thread), AUD-049 (silent failures),
AUD-045 (HouseScreen split — only with the planned House redesign, per BLOCKERS).

## What to verify after each phase

- Phase 0: `xcresulttool` summary shows 0 failed; BLOCKERS stamps updated with the bundle name.
- Phase 1: `grounding-auditor` and `pitch-truth-auditor` clean.
- Phase 2: a UI test reaches Profiles from Home; a UI test deletes a home; a unit test for "late `/score` response for a
  previous home is ignored"; manual: edit in House → re-check in Home → edit in House → object still there.
- Phase 3: backend tests for 413/422 on oversized homes, 429 on `/auth/login` floods, 409 on stale `base_revision`.
- Phase 4: live `/build` with a real HEIC photo; offline tornado drill refuses a fire plan.
- Phase 5: fresh install + upgrade install both keep all homes after the storage move.
