# S11.7 — Accounts demoted: signed-out proof, privacy copy, delete-my-data

- **Who:** P3
- **Date(s):** 2026-09-24
- **Status when I stopped:** all five mission items shipped and merged; every acceptance criterion
  that does not need a simulator is green. Nothing in this session has been rendered on a screen.

## What happened

**Mission 1 — signed-out proof.** The audit first: the only two places in the entire app that read
`AuthSession` are `RootView` (the gate) and `SettingsScreen`. Nothing else is account-gated, so
there was nothing to un-gate. The feature that *does* quietly need the network is a different axis
and worth saying plainly: `/routes`, `/score`, `/convert`, `/evacuate`, `/diff_obstructions` and
`/chat` all need a connection whether or not anyone is signed in, because they are guarded by the
build's shared `BACKEND_BEARER_TOKEN`. None of them needs an account. The editor, persistence,
drill, export and hazard hunt are entirely local.

Pinned with 7 EditorCore tests (`SignedOutProofTests`): a signed-out launch sends no request at
all, a direct `sync()` uploads nothing, the sidecar stays empty, no home document is touched, an
unreachable server is a status and nothing more, and the gate can be answered with no server
reachable. The UI half is `SignedOutPathUITests` (6 tests, new), written backend-free — base URL
points at port 1 — so it needs a simulator and nothing else. The launch-argument path the mission
asked for already existed: `-auth.gate.dismissed YES` via `NSArgumentDomain`, which seven other UI
test files already use. No test-only branch was added to the app.

**Mission 2 — privacy copy.** `escape_plan/Auth/AccountPrivacy.swift`, Foundation-only, one source
for the gate and both Settings states. The load-bearing part is `uploadedHomeKeys`: the exact set
of top-level `HomeModel` keys `POST /homes` sends, asserted against a real `HomeModel.encoder()`
run over all three fixtures. Add a field to the schema without describing it and a test fails
instead of the screen quietly becoming a lie. Rendered by `AccountPrivacyDisclosure`, collapsed by
default.

**Mission 3 — delete-my-data.** Confirmed first: **neither endpoint existed**. The S8 cloud layer
could create and update and nothing else, which is the whole reason `SyncState` carries tombstones.
Added `DELETE /auth/me` (homes first, then the user) and `DELETE /homes/{home_id}` (ownership in
the query filter, 404 for someone else's), 20 backend tests including cross-account isolation
asserted against storage rather than against a response the deleted token can no longer fetch.
Three more are `mongo`-marked for whoever has a server. On iOS: `AuthClient.deleteAccount`,
`AuthSession.deleteAccount()`, a "Delete account and data" row behind an alert, and
`SyncManager.forgetAccount` to clear the sidecar.

**Mission 4 — soft gate.** The copy was already honest in `LoginView` and `SignupView`. Two things
were not, and both changed; see decisions.md.

**Mission 5 — nothing added.** No new sign-in methods, no password reset, no email flows.

**STEP 0 was respected.** `SettingsScreen.swift` was re-read before editing. The "Share with your
fire department" rename, the two `ConsentSheet` presentations and `generateSnapshot(consent:)` are
untouched; this session's edits are confined to the ACCOUNT section, three new `@State` properties
and one `.alert`.

**Gate, measured on this branch 2026-09-24:**

| Suite | Result | Baseline at session start |
| --- | --- | --- |
| backend `-m "not live and not mongo"` | **788** passed, 1 skipped, 26 deselected | 768 |
| `swift test --package-path tools/editorcore` | **598** passed, 0 failed | 558 |
| `scripts/typecheck-ios.sh` | ok, all four targets, iOS 17.0 (app 170 files ×2, tests 82, UITests 10) | ok |
| `xcodebuild test` | **NOT RUN** — this machine cannot | — |
| backend `-m mongo` | **NOT RUN** — no Mongo server here | — |

## Decisions / surprises

Six rows in `docs/decisions.md`. The two worth reading if you only read two:

- **Account deletion erases the server completely and touches nothing on the device.** The homes
  predate the account and outlive it. `AccountPrivacy.deletionSummary` says so on screen *before*
  the user commits, and `testForgettingAnAccountNeverTouchesAHomeDocument` pins it — the promise
  and the behaviour are deliberately the same sentence.
- **The tombstone → remote-delete fix is one-directional.** A home deleted here now leaves the
  account. A home deleted on another device still does not delete here, because an absent server
  record is indistinguishable from a lost one and the reconciler correctly refuses to destroy local
  data on a guess. Closing that needs a server-side tombstone.

**Surprise worth flagging.** S8.3's decision log (2026-09-15) says "Continue without an account" is
a first-class button. What actually shipped was a grey `.subheadline` with no chrome under two 56pt
buttons. The decision and the pixels had disagreed for nine days and nobody had looked. If a
decision row describes a visual property, the pixels are the evidence, not the row.

**Correction I made to my own work.** I first wrote `testALateRefreshCannotResurrectADeletedAccount`
claiming it pinned the `generation` bump in `deleteAccount()`. Mutation-testing it showed the test
stays green with the bump removed — `refresh()`'s own `state.isSignedIn` re-check already blocks
that path. Both the test comment and the code comment now say so. The bump stays for consistency
with `signOut()`, and is described as defence in depth rather than as something a test defends.

**Two process findings.** (1) The ACCEPTANCE line names an `ecc:security-reviewer` agent that does
not exist in this environment; the `security-review` skill was run instead and found no HIGH or
MEDIUM issues. The same line appears in other playbook files and should be corrected. (2) The test
counts stamped at the top of `BLOCKERS.md` (556 backend, 516 EditorCore) are stale by several
sessions — the real baselines at my branch point were 768 and 558. I recorded mine against what I
measured and left the header alone rather than guessing which session added what.

## The review caught a bug I shipped, and it was the serious kind

`swift-scenekit-reviewer` found that the remote-delete wiring keyed off
`SyncAction.Reason.deletedOnThisDevice`, which `SyncReconciler` emits via
`SyncState.isDeletedLocally` — and that predicate **deliberately** also matches an *ownerless*
tombstone for whichever account happens to be signed in. For the question it was written to
answer ("should I download this?") that is correct and harmless. For the question I started
asking with it ("may I erase this from the cloud?") it is irreversible data loss, and the path
is built from this repo's own facts: starter homes keep fixed `home_id`s, so a fresh install
where the user deletes the seeded Bungalow *before* signing in makes exactly that tombstone, and
the first sign-in would erase their other device's real Bungalow from the account.

I reproduced it before fixing it. The fix reads the tombstone's own `ownerUserID` and requires it
non-nil and equal to the token subject.

**The lesson, because I expect to make this mistake again in a different shape:** I reused an
existing predicate for a more destructive decision than it was written for, and I checked the
call site rather than the predicate. The blast radius of a condition is set by the *new* thing it
authorises, not by the old one. `SyncState`'s own doc comment (lines 38–43) says a deletion must
only affect the account it happened in — the invariant was written down, and I still walked past
it, because I was reading the reconciler's output instead of the state's contract.

Five more findings from the same review are fixed: duplicate server records are all deleted
rather than one arbitrary one per sync; `forgetAccount` is no longer undone by an in-flight sync;
the delete alert can no longer be a silent no-op; the two new UI-test assertions on the
disclosure could never have matched (`.combine` removes the visible strings from the
accessibility tree) and are queried by identifier now; and the failed-deletion note is
dismissable. Plus three nits, including a comment that invented a `Theme.danger` token.

The two guards that are *not* merely self-consistent were mutation-checked: removing the
ownerless gate and removing the in-flight-sync guard each turn their tests red.

## Questions for teammates

- **@P1 / @P2 — whoever has a simulator:** `SignedOutPathUITests` is the one thing that can tell us
  the soft gate still works. It asserts `isHittable` on "Continue without an account", which is the
  assertion that would catch the scrollable-gate restructure going wrong on a small screen.
- **@P1 / @P2 — whoever has `MONGODB_URI`:** `pytest backend/tests/ -m mongo` now includes three
  deletion tests. The fake's `delete_many` cannot prove a real server scopes it by `user_id`, and
  getting that wrong erases every account's homes.
- **@owner:** `DELETE /auth/me` takes only the JWT, no password re-entry. Deliberate and logged.
  Say so if you want it changed before submission.

## Next steps

1. Run the iOS suite (§0 / `FIRST-PRIORITY.md`) and, in the same pass, the six new UI tests.
2. Once Render has this merge, `curl -X DELETE` a throwaway account against the deployed backend.
   S8's own history says the fakes are not enough — the `_id`-on-the-wire and `created_at` defects
   were both found only against live Atlas.
3. Decide whether the one-directional delete is acceptable for submission, or goes in `TODO.md`.
