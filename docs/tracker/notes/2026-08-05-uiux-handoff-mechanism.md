# The UI/UX handoff, and making it impossible to walk past

- **Who:** Claude Code, at Anish's request
- **Date(s):** 2026-08-05
- **Status when I stopped:** Landed and pushed. `docs/START-HERE.md` is the brief; a SessionStart
  hook and a `CLAUDE.md` block surface it. **No app code was touched** — this session is docs and
  Claude Code configuration only.

## What happened

Anish asked for two things: get everything committed and synced to `main`, and leave an
instruction the whole team's Claude Code sessions cannot walk past — one that immediately tells
whoever sits down that the engineering is done and the remaining work is manual UI/UX on a real
device.

### The mechanism

Three pieces, deliberately redundant:

| Piece | Role |
|---|---|
| `docs/START-HERE.md` | The actual brief. Front-matter `handoff_status: active` drives everything else. |
| `.claude/hooks/session-start/handoff-banner.sh` | SessionStart hook. Injects the banner into session context before the user's first message. Self-silences when the flag reads `closed`. |
| Block at the top of the root `CLAUDE.md` | Same words, for anyone whose harness doesn't run this repo's hooks. |

`.claude/settings.json` and `CLAUDE.md` are both tracked, so this reaches teammates on their
next pull with no setup.

### Why redundant rather than one clean mechanism

The hook is strictly better when it fires — it lands before the user's first message, so it beats
a clarifying question. But it only fires for someone running Claude Code who has trusted this
project's hooks. `CLAUDE.md` is always read. Neither is *literally* unskippable: both instruct
the model, and a model can decline. That's why the banner is short, states the three traps
inline rather than only linking to them, and explicitly says to help the user with whatever they
actually asked instead of hijacking the session — an instruction that hijacks sessions gets
deleted within a week.

### Why a kill switch, and why it's a flag rather than deleting the hook

The one prediction I'm confident about: a nag with no off switch gets ripped out. So closing the
handoff is one word in one file, the README says to close it rather than delete the hook, and the
hook reads only the first ten lines of the brief so the word `closed` appearing in prose can't
accidentally disarm it. Verified both directions by running the hook against a temp copy:
`active` → valid JSON, 1943 chars; `closed` → zero output, exit 0.

### What the brief actually says

Not "polish the UI" — that produces a session of wandering the codebase changing colours. It is
ordered by what a person holding a phone should do first:

1. **What's already done, so it doesn't get rebuilt.** Several decisions look like bugs without
   their reasoning — reserved route orange, the rejected one-colour-per-person idea, the
   deliberately logo-less launch screen.
2. **Two setup steps before any device build.** The `BackendConfig.local.json` bearer token is
   the one that matters: without it a fresh install 401s on everything and reads as a broken app.
3. **Known-dead, do not debug:** the Anthropic account is out of credits, so 502s from
   `/explain`, `/analyze` and `/chat` are expected. That is the single most likely way to lose a
   whole session to a billing problem.
4. **The job:** camera feel (the four hold-it-in-your-hand checks, with the thumb-tracking one
   first because it gates the rest), then frame time measured on hardware, then the golden path
   walked as a judge would, then the visual pass.
5. **Rules that don't bend**, and a checkable definition of done.

## Decisions / surprises

One row in `docs/decisions.md`. The reasoning worth keeping: the reliable place to put "here is
what you should be working on" is the session context, not a document someone has to remember to
open — every teammate drives this repo through Claude Code, so that's where it goes.

**Surprise:** `docs/tracker/TODO.md` is 490 lines and correct, and that is exactly why it doesn't
work as a handoff. It's grouped by area, not by what a person with a phone should do first, and
the device work is scattered across four separate sections (`Needs a physical device`,
`iOS — real code gaps`, `Demo & submission`, plus the camera section). Nobody opening it cold
would assemble the right first hour out of it. The brief doesn't replace it — it orders a slice
of it and points back.

## Questions for teammates

- **@Anish** — the banner names you by name and speaks in your voice. Read
  `docs/START-HERE.md` §1 and the block at the top of `CLAUDE.md` and change anything you
  wouldn't actually say. I wrote what the tracker supports, not what you dictated.
- **@Anish** — the bearer token is still missing on your machine (confirmed 2026-08-05 by
  `scripts/demo-preflight.py`). Whoever does the device pass needs it before they can do
  anything. That's the real first blocker, ahead of any UI work.
- **@team** — if the banner gets annoying, set `handoff_status: closed` in
  `docs/START-HERE.md`. Please don't delete the hook; the next handoff will want it.

## Next steps

1. The UI/UX pass itself — `docs/START-HERE.md` §3, in order. Needs a physical iPhone.
2. Top up the Anthropic account. Nothing else on the list is closer to the critical path.
3. Close the handoff when §5's checklist is done.
