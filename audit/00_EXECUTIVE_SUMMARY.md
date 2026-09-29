# 00 · Executive Summary — Escape Plan full-repository audit

**Date:** 2026-09-28 · **Branch:** `drill-3d-fallback` at `3dc9c8e` (2 commits ahead of `origin/main`, unpushed) ·
**Scope:** iOS app, FastAPI backend, schema, corpus, tooling, CI, deployment config, tracker docs ·
**Mode:** audit only — no source file was changed; this `audit/` directory is the only output.

## How to read this directory

| File | What |
|---|---|
| `01_ARCHITECTURE.md` | System map, trust boundaries, data ownership, architectural root causes |
| `02_FRONTEND.md` … `14_FEATURE_COMPLETENESS.md` | Domain reports; each finding written in full **once**, in its "home" file |
| `15_PRIORITIZED_ISSUES.md` | **Master index** — every ID, severity, location, dependencies, home file, status, root-cause groups |
| `16_RECOMMENDED_IMPLEMENTATION_ORDER.md` | Phased plan with the reason for each ordering |
| `17_VERIFICATION_LOG.md` | Every command run, with results, so claims can be re-checked |

Each finding uses the template: Severity · Location · Category · What I found · Current · Expected · Why it matters ·
Evidence · Affected systems · Root cause · Fix direction · Dependencies. Severity: **P0** production-blocking or
data-loss critical; **P1** major feature/flow broken or serious security/reliability risk; **P2** meaningful bug;
**P3** minor. Status **Known** means it is already on `docs/tracker/BLOCKERS.md`.

This repo has no web frontend and no Vercel deployment; "frontend" means the iOS app and "deployment" means Render.

## Health at a glance (measured today)

| Gate | Result |
|---|---|
| Corpus validator | valid (36 sources, 13 files, 44 tips) |
| Backend pytest (not live) | **893 passed**, 1 skipped, 29 deselected |
| EditorCore `swift test` | **614 passed**, 0 failed |
| iOS type-check (4 targets) | ok |
| iOS simulator suite | **987 total: 972 passed, 7 failed, 8 skipped** — all 7 failures are test-side (keychain entitlement, stale expectation, UI-test isolation) |
| Deployed backend | up (`/health` 200 after a **51 s** cold start), DB ok, `/diff_obstructions` correctly 401 without token |

The engineering core is strong: deterministic routing with no AI in it, one schema kept in lockstep across three
languages, contract tests that have caught real drift, and careful cloud ownership rules. **The problems are almost all
at the seams** — between screens that write the same file, between the revamped UI and features it stopped linking to,
between client copy and server behaviour, and between a public app and a backend that trusts a shared token.

## 1. Issues by severity

| P0 | P1 | P2 | P3 | Total |
|---|---|---|---|---|
| 1 | 13 | 19 | 17 | **50** |

The P0 (AUD-001, deployed token mismatch) is carried from BLOCKERS and is owner-only; it could not be re-verified
without reading a secret. 8 of the 50 were already on BLOCKERS in whole or in part (AUD-001, 002, 003, 006, 019, 036, 045, 047); the rest are new or newly root-caused.

## 2. Major architectural findings

- **One home file, many writers, no owner** (R1): House keeps a long-lived in-memory copy that never reloads, while
  Home, onboarding and sync write the same file → silent overwrites (AUD-013, AUD-015, AUD-017).
- **The Linear revamp deleted the old hub (`BetaScreen`) without re-homing its actions** (R2): Profiles, delete,
  duplicate, export and the post-build review step all vanished from the UI (AUD-020, AUD-021, AUD-023).
- **Features wired on one side only** (R4): `/analyze` and `/explain` have no UI (AUD-022); checklist recurrence exists
  server-side but no caller can use it (AUD-026); JSON import has no UI.

## 3. Major security findings

- **AUD-003** The "secret" bearer token ships inside every app build, and the AI rate limiter keys on a client-supplied
  header — spend is effectively unbounded for anyone holding the app.
- **AUD-004** No bounds on home size: route cost grows with floor area (measured 7.2 s per plan at 10× a fixture;
  `/score` runs three plans) → one request can pin the single free instance.
- **AUD-005** `/auth/register` and `/auth/login` are unthrottled and run Argon2 on the event loop (36 ms per verify
  locally, far more on Render) → brute force and whole-service stalls.
- **AUD-050** The sign-in screen's privacy copy says signed-out use "uploads nothing about your home" and "no photo is
  ever sent"; in fact every route/score/chat call sends the full home (names, vulnerability tags, optional address), and
  Import Plan sends photos on to Anthropic.
- **AUD-008** The whole Documents folder (homes, sync sidecar, chats, raw scans) is browsable and editable in the Files
  app in Release builds.
- Solid: JWT handling, per-user ownership in every query, no secrets in git, deployed guard fix confirmed live.

## 4. Major functional findings

- **AUD-020** Household profiles cannot be added or edited after onboarding; the drill tells users to "Add family
  members in Profiles first" and there is no Profiles screen → the drill is a dead end for a user's own scanned home.
- **AUD-021** Homes cannot be deleted or duplicated; demo homes, abandoned blank homes and conflict copies accumulate.
- **AUD-023** AI-drafted homes are scored immediately, contradicting the spec's "mandatory editor review".
- **AUD-024** Photo-based Import Plan sends HEIC/JPEG bytes labelled PNG → expect a 502 "AI unavailable".
- **AUD-025** The drill appends its own unconditional "Leave immediately…" tornado instruction to an engine finding that
  only applies to mobile/manufactured homes — client-authored safety guidance, the thing the project promises never
  happens.
- **AUD-022** The demo script's "AI inspector" beat cannot be filmed from the current build.
- **AUD-026** "Practice twice a year" and "rescan" never go stale; "test alarms monthly" never recurs.

## 5. Major UX findings

- Dead ends: drill without profiles (AUD-020); no way to remove homes (AUD-021).
- Wrong data shown: previous home's score after a switch (AUD-014); wrong home shared with the fire department from
  Settings (AUD-027); another peril's/person's cached route offline (AUD-028).
- Misleading errors: first chat after idle says "You're offline" (AUD-032); a cancelled request says "Couldn't reach the
  server" (AUD-014/046); a failed re-check says the score failed and its Retry imports an old scan (AUD-029).
- Silent failures on several user writes (AUD-049); silent sign-out after 60 minutes (AUD-031).

## 6. Major deployment / reliability findings

- **AUD-034** The drill fix exists only on the audit machine (`origin` has only `main`).
- **AUD-001 / AUD-002** (known, owner-only) token mismatch and exhausted AI credits block the demo path and all AI.
- **AUD-037** Render deploys independently of CI (low confidence — dashboard not visible); the iOS suite is manual-only.
- **AUD-032** 51 s cold start measured; chat's 60 s timeout cannot absorb it.
- **AUD-035** AI calls have no timeouts or input caps; server loops outlive the client.
- **AUD-016 / AUD-015** Sync can lose a concurrent update server-side and can multiply conflict copies client-side.
- **AUD-038** `tools-used.md` may omit an AI agent tool evidenced on the machine — a CAC disclosure question for the owner.

## 7. Recommended implementation phases (details in 16)

0. **Unblock** — push/merge the drill fix, owner fixes token and credits, make the iOS suite green (test-side fixes),
   correct the tracker.
1. **Truthfulness & safety copy** — remove client-authored tornado text, fix privacy copy, stop scoring AI drafts, decide
   analyze/explain.
2. **Data integrity & core flows (iOS)** — single owner for a home (AUD-013) *first*, then Profiles, delete/duplicate,
   score race, sync ordering.
3. **Backend hardening (parallel)** — size bounds, auth throttling, AI budget/timeouts, quotas, revision
   compare-and-set.
4. **Integration correctness** — photo transcoding, recurrence, cache keys, timeouts, error labels.
5. **Storage & session** — Files-app exposure and storage move, token settings, session refresh.
6. **Grounding depth & CI** — uncited-claim checks, nightly iOS suite, deploy gating.
7. **Cleanup** — disclosure, scratch files, dead code, main-thread listing, silent failures.

## 8. Where confidence is low

- **Deployed secrets and billing** (AUD-001, AUD-002): not re-verified — reading `.env` is blocked by the repo's secrets
  guard (correctly) and a live AI call would spend credit.
- **Anthropic's exact response to a mislabelled/oversized image** (AUD-024): reasoned from the API's documented
  constraints, not observed.
- **TabView lifecycle half of AUD-013** (does `onDisappear` fire on tab switch, clearing the sync guard): standard SwiftUI
  behaviour, not reproduced here; the stale-copy overwrite half does not depend on it.
- **Render auto-deploy gating** (AUD-037): the dashboard setting is not visible from the repo.
- **Device-only paths** (LiDAR scan, AR drill, re-check alignment on real scans, iOS 17 runtime behaviour): not
  testable here; they remain on BLOCKERS §2 and were not re-audited.
- **`testSettingsCarriesThePrivacyDisclosureSignedOut`** cause (needs scrolling): inferred; confirm from the result
  bundle screenshot.
- **AUD-038**: worktrees prove a tool touched the repo, not what it contributed.
- **Not audited in depth:** the SceneKit renderer internals, `PersonFixture`/gait animation, PDF layout, and the
  routing/hazard algorithms beyond their inputs (they carry 893 passing tests and several prior audits).
