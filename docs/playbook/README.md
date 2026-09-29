# Playbook: the S11 arc

Everything before S11 is shipped and lives in git history: `git show archive/playbook-v1:docs/playbook/<file>`.
The product spec is [`01-product-spec.md`](01-product-spec.md). Status lives in
[`../tracker/BLOCKERS.md`](../tracker/BLOCKERS.md). **Deadline: submit by Oct 24, 2026.**

## The 13 sessions

Three people, three lanes, disjoint file ownership. **Lane C needs the machine with the simulator and the
physical iPhone 17 Pro.** Assign people to lanes however you like; run a session with `/session S11.4`.

| # | Session | Lane | Branch | Prereqs |
|---|---|---|---|---|
| [S11.1](S11-1.md) | Earthquake + tornado corpus depth, cited prevention tips | A | `s11-1-corpus-depth` | baseline |
| [S11.2](S11-2.md) | Peril scoring and checklist from the new corpus, honest tiering | A | `s11-2-peril-scoring` | S11.1 |
| [S11.3](S11-3.md) | Object-hazard QA (BUG-01..04) and the future-detection scoping doc | A | `s11-3-hazard-qa` | baseline |
| [S11.4](S11-4.md) | AI layer: positioning, evals, credit-independent tests | A | `s11-4-ai-layer` | baseline |
| ~~S11.5~~ | ~~Readiness Home and the prevention layer~~ **DONE 2026-09-23** | B | `s11-5-readiness-home` | baseline (tips: S11.1) |
| ~~S11.6~~ | ~~Responder Snapshot v2, "Share with your fire department"~~ **DONE 2026-09-23** | B | `s11-6-responder-snapshot` | baseline |
| ~~S11.7~~ | ~~Accounts demoted: signed-out proof, privacy, delete-my-data~~ **DONE 2026-09-24** | B | `s11-7-accounts-demoted` | baseline |
| [S11.8](S11-8.md) | iOS verification: first full simulator run in nine days | C | `s11-8-ios-verify` | baseline |
| [S11.9](S11-9.md) | Device pass I: camera, frame rate, framing, floors | C | `s11-9-device-camera` | S11.8 |
| [S11.10](S11-10.md) | Device pass II: real scan, AR Drill, haptics, VoiceOver, print | C | `s11-10-device-drill` | S11.9 |
| [S11.11](S11-11.md) | Integration gate and golden-path polish | all | `s11-11-integration` | S11.1-S11.10 |
| [S11.12](S11-12.md) | Pitch v2: script, storyboard, truth audit | any | `s11-12-pitch-v2` | drafts early; truth pass after S11.11 |
| [S11.13](S11-13.md) | Film, edit, submit | all | `s11-13-film-submit` | S11.11, S11.12 |

```
baseline --+--> A: S11.1 --> S11.2
           |       S11.3 , S11.4        (parallel with S11.1)
           +--> B: S11.5 , S11.6 , S11.7 (parallel)
           +--> C: S11.8 --> S11.9 --> S11.10
                              all lanes --> S11.11 --> S11.12 --> S11.13
```

## Audit remediation arc: S11.14 to S11.49 (added 2026-09-28)

The full-repository audit of 2026-09-28 (`audit/`, 50 findings; start at `audit/00_EXECUTIVE_SUMMARY.md`, master index
`audit/15_PRIORITIZED_ISSUES.md`, plan `audit/16_RECOMMENDED_IMPLEMENTATION_ORDER.md`) is turned into the 36 sessions
below. **Which session fixes which finding:** [`audit-traceability.md`](audit-traceability.md), which also lists what
was deliberately not made into a task, and why. These sessions come **before S11.11**: the integration gate should run
on a `main` that has them.

**Lanes.** **D** is iOS remediation. It is strictly serial in number order, because its sessions share `HomeScreen`,
`ReadinessStore`, `HouseScreen` and `DrillScreen`. **E** is backend remediation, serial within the lane (shared
`main.py`, `api_auth.py`, `cloud_repo.py`) and parallel to D. **Any** is docs, CI or owner work. Lane D can run
alongside S11.9 (renderer). It must **not** run alongside **S11.10**, which owns `DrillMode/**`: S11.15, S11.18,
S11.20, S11.35 and S11.36 each make a small edit to `DrillScreen.swift`.

**Cross-lane hand-offs.** S11.26 comes before S11.33 and S11.45 (server limits before the client matches them).
S11.29 comes before S11.37 (server chat deadline shorter than the client timeout). **S11.30 must be deployed before
S11.32 ships, and S11.34 before S11.35**: the request models are `extra="forbid"` or `bool`-only, so a new client
talking to an old server gets 422. S11.27 and S11.29 come before S11.39 (spend controls before more AI is reachable).

**If you work top to bottom, this order respects every prerequisite:**
S11.14 → **S11.8** (existing, with the addendum below) → S11.15 → S11.16 → … → S11.49 (numeric order) → S11.11.

**Minimum before filming** (every P0/P1 item, if the calendar forces a cut): S11.14, S11.8, S11.15-S11.21, S11.25-S11.28,
S11.33 and S11.39. The owner actions (token, credits, the AUD-022 and AUD-038 answers) sit outside any session.
Anything cut gets a BLOCKERS line.

| # | Session | Audit IDs | Top sev | Phase | Lane | Branch | Prereqs | Status |
|---|---|---|---|---|---|---|---|---|
| [S11.14](S11-14.md) | Land the drill fix, commit the audit, make the tracker true | 034, 048 (asks owner: 001, 002, 022, 038) | P0/P1 | 0 Baseline | any | `drill-3d-fallback`, then `s11-14-tracker-truth` | none | |
| [S11.8](S11-8.md) | iOS verification (existing session; see addendum) | 036 | P2 | 0 Baseline | C | `s11-8-ios-verify` | S11.14 | |
| [S11.15](S11-15.md) | Drill shows engine findings verbatim, no client tornado advice | 025 | P1 | 1 Truth | D | `s11-15-drill-verbatim` | S11.14 | |
| [S11.16](S11-16.md) | Privacy copy says what actually leaves the phone | 050, 018 | P1 | 1 Truth | D | `s11-16-privacy-truth` | S11.14 (after S11.8 for UI tests) | |
| [S11.17](S11-17.md) | An AI draft goes to the editor, not to the score | 023 | P1 | 1 Truth | D | `s11-17-draft-review` | S11.14 | |
| [S11.18](S11-18.md) | One HomeDocumentStore for the whole app | 019 | P3 (R1 foundation) | 2 Data integrity | D | `s11-18-one-store` | S11.14 | |
| [S11.19](S11-19.md) | House editor reloads when its home changes underneath it | 013, 045 (seam) | P1 | 2 Data integrity | D | `s11-19-house-reload` | S11.18 | |
| [S11.20](S11-20.md) | Household profiles are reachable again | 020, 044 | P1 | 2 Data integrity | D | `s11-20-profiles-reachable` | S11.19 | |
| [S11.21](S11-21.md) | Delete and duplicate homes; no blank home until the first edit | 021, 039 | P1 | 2 Data integrity | D | `s11-21-home-delete` | S11.19 | |
| [S11.22](S11-22.md) | Sync: at most one conflict copy, never while open | 015 | P2 | 2 Data integrity | D | `s11-22-sync-conflict-copies` | S11.19, S11.21 | |
| [S11.23](S11-23.md) | A score belongs to the home it was asked for | 014 | P2 | 2 Data integrity | D | `s11-23-score-race` | S11.17 | |
| [S11.24](S11-24.md) | Re-check a room end to end | 017, 029, 049 | P2 | 2 Data integrity | D | `s11-24-recheck-flow` | S11.19, S11.23 | |
| [S11.25](S11-25.md) | Residential size bounds, server and editor alike | 004 | P1 | 3 Backend hardening | E | `s11-25-home-bounds` | S11.14 | |
| [S11.26](S11-26.md) | Request size limits and input caps | 004, 035, 024 | P1 | 3 Backend hardening | E | `s11-26-request-limits` | S11.14 | |
| [S11.27](S11-27.md) | AI spend ceiling; trusted client key; one require_token | 003, 006, 043 | P1 | 3 Backend hardening | E | `s11-27-ai-spend` | S11.14 | |
| [S11.28](S11-28.md) | Sign-in routes: off the event loop, throttled, rehash | 005, 011 | P1 | 3 Backend hardening | E | `s11-28-auth-throttle` | S11.27 | |
| [S11.29](S11-29.md) | AI calls time out and stop when the phone gives up | 035 | P2 | 3 Backend hardening | E | `s11-29-ai-deadlines` | S11.26, S11.27 | |
| [S11.30](S11-30.md) | Cloud homes: quota and compare-and-set revisions | 016, 007 | P2 | 3 Backend hardening | E | `s11-30-homes-cas` | S11.26, S11.28 | |
| [S11.31](S11-31.md) | Backend hygiene: /convert errors, index retry, /health commit | 010, 042, 037 | P2 | 3 Backend hardening | E | `s11-31-backend-hygiene` | S11.30 | |
| [S11.32](S11-32.md) | Sync handles a stale revision and a full account | 016, 007 | P2 | 4 Integration | D | `s11-32-sync-cas` | S11.22, S11.30 deployed | |
| [S11.33](S11-33.md) | Photo import sends a real JPEG | 024 | P1 | 4 Integration | D | `s11-33-photo-jpeg` | S11.26 | |
| [S11.34](S11-34.md) | Checklist recurrence through /score (server) | 026 | P2 | 4 Integration | E | `s11-34-recurrence-server` | S11.27 | |
| [S11.35](S11-35.md) | The app remembers when a recurring task was done | 026 | P2 | 4 Integration | D | `s11-35-recurrence-app` | S11.23, S11.34 deployed | |
| [S11.36](S11-36.md) | Offline route cache keyed by peril, person and model | 028 | P2 | 4 Integration | D | `s11-36-route-cache-key` | S11.20 | |
| [S11.37](S11-37.md) | Failure messages tell the truth | 032, 046, 014 | P2 | 4 Integration | D | `s11-37-honest-failures` | S11.23, S11.29 | |
| [S11.38](S11-38.md) | Settings share uses the active home, reports failures | 027, 049 | P2 | 4 Integration | D | `s11-38-settings-share` | S11.21 | |
| [S11.39](S11-39.md) | AI inspector: wire it or cut the claim | 022, 044 | P1 | 4 Integration | D + E | `s11-39-ai-inspector` | S11.14 decision, S11.27, S11.29 | |
| [S11.40](S11-40.md) | Release builds keep data out of Files; scans cleaned | 008 | P2 | 5 Storage & session | D | `s11-40-release-files` | S11.24 | |
| [S11.41](S11-41.md) | Home ids validated on every write | 012 | P3 | 5 Storage & session | D | `s11-41-home-id-validation` | S11.21, S11.40 | |
| [S11.42](S11-42.md) | Server settings: rotation reaches installs, bad URLs refused | 009 | P2 | 5 Storage & session | D | `s11-42-server-settings` | S11.14 owner answers | |
| [S11.43](S11-43.md) | Signing in lasts; expiry is announced | 031 | P2 | 5 Storage & session | D + E | `s11-43-session-length` | S11.16, S11.28 | |
| [S11.44](S11-44.md) | Chat rejects uncited safety claims | 030 | P2 | 6 Grounding & CI | E | `s11-44-chat-citations` | S11.29 | |
| [S11.45](S11-45.md) | One conversation per home, bounded history | 033, 049 | P3 | 6 Grounding & CI | D | `s11-45-conversation-per-home` | S11.26, S11.37 | |
| [S11.46](S11-46.md) | Nightly iOS suite; Render deploys only green commits | 037 | P2 | 6 Grounding & CI | any | `s11-46-ci-gating` | S11.8, S11.31 | |
| [S11.47](S11-47.md) | Repo hygiene: scratch scripts, dead code, Python 3.12 | 040, 041, 044, 038 (file) | P3 | 7 Cleanup | any | `s11-47-repo-hygiene` | S11.46 | |
| [S11.48](S11-48.md) | Library listing off the main thread (optional) | 047, 049 | P3 | 7 Cleanup | D | `s11-48-library-listing` | S11.21, owner agrees | |
| [S11.49](S11-49.md) | Live AI verification once credits exist | 002 (+ live 022, 024, 030, 035) | P1 | 7 Verification | any | `s11-49-live-ai` | owner top-up, S11.29, S11.33, S11.44 | |

```
S11.14 --> S11.8 ----------------------------------------------------------> S11.46 --> S11.47
   |
   +--> D: S11.15 -> S11.16 -> S11.17 -> S11.18 -> S11.19 -> S11.20 -> S11.21 -> S11.22 -> S11.23 -> S11.24
   |        -> S11.32* -> S11.33* -> S11.35* -> S11.36 -> S11.37* -> S11.38 -> S11.39* -> S11.40 -> S11.41
   |        -> S11.42 -> S11.43* -> S11.45* -> S11.48
   |
   +--> E: S11.25 , S11.26 -> S11.27 -> S11.28 -> S11.29 -> S11.30 -> S11.31 -> S11.34 -> S11.44
   |
   +--> owner: token (AUD-001), credits (AUD-002) -----------------------------> S11.49 --> S11.11
   (* = waits on a Lane E session: 32<-30 deployed, 33<-26, 35<-34 deployed, 37<-29, 39<-27+29, 43<-28, 45<-26)
```

**Addendum to S11.8 (AUD-036; the S11.8 file predates the audit).** The audit ran the full suite on 2026-09-28: 987
total, 972 passed, 7 failed, 8 skipped. All seven failures are test-side, with three root causes (full write-up in
`audit/11_TESTING.md`):
(1) `KeychainTokenStoreTests` ×3 fail with `-34018` (errSecMissingEntitlement) because the test host is unsigned under
`CODE_SIGNING_ALLOWED=NO`. Prove the store works with one ad-hoc-signed run (`CODE_SIGN_IDENTITY=-`), then either sign
the gate run or skip with a reason when the entitlement is missing (a skip needs a BLOCKERS line, per S11.8's RULES).
(2) `EvacuationMockTimelineTests` expects 1 apartment track; the fixture has had 2 profiles (Sam and Biscuit) since
2026-09-16. Confirm the pet track is intended (the renderer has a pet gait), then update the expectation. The file is
`#if !SWIFT_PACKAGE`, so it never ran in EditorCore; BLOCKERS §3's "passes in EditorCore" is wrong (S11.14 corrects it).
(3) `SignedOutPathUITests`: the two gate tests fail because `-auth.gate.dismissed` persists on the simulator; pass
`-auth.gate.dismissed NO` (and `-onboarding.completed YES`) explicitly. `testSettingsCarriesThePrivacyDisclosureSignedOut`
likely needs a scroll to the disclosure button (medium confidence: check the result bundle's screenshot first).
S11.8's missions 1, 2 and 4 still apply; mission 5's auth-gate point is (3). Run S11.8 right after S11.14, so every
later session compares against a green suite.

**Addendum to S11.11.** Its prereqs now also include the remediation sessions (at least the "minimum before filming"
set above) and S11.49 for the AI half of the gate.

**Note on `backend/app/ai/`.** CLAUDE.md's trap "Only touch `backend/app/ai/` in session S11.4" predates this arc.
S11.26, S11.29 and S11.44 (and S11.49, for a proven defect only) are each scoped to name exactly which parts of `ai/`
they may edit. A live 502 is still billing, not code.

**Template addition.** Each remediation prompt keeps the session template below and adds an AUDIT block: the IDs,
their severity, where the full write-up is, and a reminder that the audit's line numbers are from `3dc9c8e`, so code
is found by symbol and each finding is re-confirmed on `origin/main` before it is fixed.

## Branch protocol (every session prompt repeats this)

1. `git fetch origin && git switch -c <branch> origin/main` (or `git worktree add ../ep-<slug> -b <branch> origin/main`).
2. Work only on that branch. **Never commit to `main`** (a hook blocks it). Touch only the session's OWNED FILES.
   Anything else you find goes into `BLOCKERS.md`, not into your diff.
3. Commit small. Confirm `git branch --show-current` before each commit.
4. Finish: `git fetch origin && git merge origin/main`, re-run the session's ACCEPTANCE, run its auditor agent,
   then `git switch main && git pull && git merge --no-ff <branch> && git push`. No human sign-off and no PR gate.
5. Never rewrite shared history (no force-push, no rebase of anything already pushed).

## Conflict rules

- File ownership is disjoint by design. If you need a file another lane owns, stop and log it.
- Shared files are append-only inside **your own section**: `BLOCKERS.md`, `TODO.md`, `docs/decisions.md`.
  `decisions.md` and `activity-log.md` use `merge=union` (`.gitattributes`), so concurrent appends do not conflict.
- Add a session note under `docs/tracker/notes/` (copy `_TEMPLATE.md`). Its filename is unique to you.

## Session template

`S11.N: title, ~hours, Lane, Prereqs, blocks` then Context, then one fenced prompt containing: BRANCH,
OWNED FILES, MISSION, RULES, DELIBERATELY NOT IN THIS SESSION, ACCEPTANCE (commands plus the auditor agent),
CLOSE OUT.

## End of session

Update your section of `BLOCKERS.md` (and `TODO.md` if the backlog moved), write the note, log deviations in
`decisions.md` and new dependencies in `docs/tools-used.md`. Remove a BLOCKERS line only when you personally
verified it. No note, no DONE.

## Archive tags

`archive/playbook-v1` (the old playbook), `archive/pre-s11-main` (local main before the merge),
`archive/pre-s11-origin` (origin/main before the merge), `archive/s8-cloud-sync` (accounts arc before demotion).
