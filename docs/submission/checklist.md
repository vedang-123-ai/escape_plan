# Submission checklist

_Written 2026-10-05 (S11.51). Sources: the official **2026 CAC Rules** PDF
(`congressionalappchallenge.us/wp-content/uploads/2026/05/2026-CAC-Rules.pdf`, read 2026-10-05), the CAC rules page,
`docs/playbook/S11-12.md`, `docs/playbook/S11-13.md` and BLOCKERS §5. The rules point to a separate "Submission
Checklist" on the portal that we could not read from here; check it when you log in._

**Key:** `DONE` = finished and checked in the repo · `DRAFTED` = written, a person must review it · `PERSON` = only a
person can do it · `BLOCKED` = waiting on something else.

**Deadline: 12:00 pm EDT, Monday, October 26, 2026** (rules §5). Our own target is Oct 24. After the deadline the
submission "cannot be modified in any way" (rules §4).

## Eligibility and registration (rules §1, §2)

| Item | Status | Notes |
|---|---|---|
| Every team member is enrolled in middle or high school on Oct 26, 2026 | PERSON | |
| Team has at most 4 students; at least half live or go to school in the same district | PERSON | Commit authors on `main` are `vedang-123-ai`, Anish Yarrakonda and Yuki Tanaka; 22 more commits are authored by "Claude" (an AI agent, not a team member). Confirm who is on the entry |
| The district is hosting a 2026 App Challenge | PERSON | Check on the CAC site |
| Each person enters only one app, in one district | PERSON | |
| App was created after Oct 30, 2025 | DONE | First commit on `main` is 2026-07-10 |
| Register: personal (not school) email, home address with 9-digit ZIP, district and Member of Congress; school address with 9-digit ZIP; a parent or guardian's name and email; coding teacher or mentor (optional) | PERSON | For every team member |
| One teammate creates the team profile and invites the others; everyone completes a personal profile and the eligibility quiz | PERSON | The application opens after the eligibility email arrives |

## Demonstration video (rules §4)

| Item | Status | Notes |
|---|---|---|
| Length 1 to 3 minutes, **maximum 3:00** | PERSON | Older notes say "under 3:15"; that is wrong for 2026 (BLOCKERS, S11.51). `script-v2.md` VO is about 1:34 on paper; the time that counts is the finished cut |
| Says the name of each participant | PERSON | Not in `script-v2.md` yet (BLOCKERS, S11.51) |
| Says the app's name | DRAFTED | `script-v2.md` Beat 1 |
| States the purpose in one clear sentence | DRAFTED | Suggested sentence in [`written-answers-draft.md`](written-answers-draft.md) Q2; not in the script yet |
| Says who the app is for (target audience) | PERSON | Not stated plainly in `script-v2.md` (BLOCKERS, S11.51) |
| Says the tools and coding languages used | PERSON | Not in `script-v2.md` (BLOCKERS, S11.51). Short list in `written-answers-draft.md` "How does it work?" |
| Shows the app working | BLOCKED | Needs filming on the device (S11.13). `python3 scripts/demo-preflight.py` must pass right before filming |
| A pre-built or earlier-scanned home is described accurately | PERSON | An organizer confirmed this is acceptable if described accurately (`docs/tracker/field-test-lidar.md`). Never narrate a scan that did not make the model shown |
| The AI assistant is shown only if the Anthropic account is funded and preflight passes | BLOCKED | Credits are out (BLOCKERS AUD-002). Otherwise cut Beat 5 (decisions 2026-10-04, S11.12) |
| No keys or tokens on screen | PERSON | Settings "Advanced" is hidden in Release builds; film a Release build |
| Three non-team viewers name the wow moment unprompted | PERSON | S11.13 acceptance |
| Upload to YouTube or Vimeo, set to **public** | PERSON | Unlisted or private does not meet the rule |

## Written answers and descriptions (rules §3, §4)

| Item | Status | Notes |
|---|---|---|
| Title, purpose, inspiration, technical difficulty, what we learned, 2.0 version | DRAFTED | [`written-answers-draft.md`](written-answers-draft.md) |
| App description | DRAFTED | [`app-description.md`](app-description.md), under 250 words (`wc -w` on the text below its `---` line) |
| What we learned, including how the firefighter interview changed the product | DRAFTED | [`what-we-learned.md`](what-we-learned.md) |
| All open-source libraries, frameworks and external tools documented | DONE | [`../tools-used.md`](../tools-used.md), completed 2026-10-05 |
| All AI usage fully disclosed | DRAFTED | `tools-used.md` "AI tools used to build the app". A person must confirm the list is complete (owner said Claude and Google Antigravity/Gemini only, 2026-09-29) |
| A statement of each member's own contribution and understanding | PERSON | The rules: AI "must not constitute the entirety of the technical development". 513 of 634 non-merge commits carry a Claude co-author line, so this sentence matters (BLOCKERS, S11.51) |
| Firefighter: not named or quoted unless he agrees | PERSON | S11.13 emails him. All drafts here say only "a working firefighter" |

## Judges' access (rules §7)

| Item | Status | Notes |
|---|---|---|
| Be able to give judges the app and the source code on request | PERSON | The repo is private (`vedang-123-ai/escape_plan`). Decide how: add a judge as a GitHub collaborator, or send a zip. Decide how a judge runs the app (TestFlight or in person). Refusing a request means disqualification |
| The deployed backend is up and its token matches the app | PERSON (last verified 2026-09-29) | Preflight passed `/routes` and `/score` on 2026-09-29; re-run `python3 scripts/demo-preflight.py` before submitting |

## After submitting

| Item | Status | Notes |
|---|---|---|
| Save the confirmation screenshot under `docs/evidence/` | PERSON | S11.13 |
| Tag the submitted commit `submitted-cac-2026`; set `handoff_status: closed` in `docs/START-HERE.md` | PERSON | S11.13 |
| Every team member completes the Exit Questionnaire individually | PERSON | Link arrives after the deadline (rules §6) |

## Not verified, and must not be claimed as verified

- Live AI behaviour (assistant, Import Plan). Verified in stub tests only; the account is out of credits.
- The final build on a real iPhone. The §2 device-pass checklist in BLOCKERS has not been done. A real LiDAR scan of a
  friend's house did work on 2026-09-08, on an earlier build.
- Render's "deploy after checks pass" dashboard setting (BLOCKERS §1).
