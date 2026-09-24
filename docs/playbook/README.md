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
