# S3.2 — `check_obstructions` agent tool

- **Who:** vedang
- **Date(s):** 2026-08-02
- **Status when I stopped:** tool wired, prompt updated, 6 deterministic tests green
  (backend 248 → 258), corpus valid. **The live case has never executed** — no API key on
  this machine.

## What happened

Picked up the one open TODO item that wasn't blocked on hardware, a key, or a human:
"give the S3.2 agent a `check_obstructions` tool." The deterministic half
(`app/routing/obstructions.py`, 2026-07-24) was already built, tested, and feeding `/routes`
and `/score` — it just had no path to the AI layer, so "a wardrobe is parked in front of your
bedroom door" could only ever appear as a checklist row. Never in an explanation, never in
chat.

- `check_obstructions` in `TOOLS` + `_dispatch_tool`, optional `room_id` filter. Returns
  `analyze_obstructions`' fields verbatim, including its `detail` sentence.
- Prompt rule 1 now forbids estimating a clearance or a move distance in as many words; rule
  2 lists the tool in the systematic sweep; rule 4 maps `blocks_opening` / `narrows_route` to
  severities.
- 6 tests: attribution + measured move, the `room_id` filter, a furniture-free home, the
  read-only guarantee, tool registration, and a scripted end-to-end loop that files a
  `usfa-escape-plans`-cited finding off a real obstruction call.
- A third live case (`test_blocked_bungalow_agent_names_the_wardrobe`) asserting the model
  calls the tool and quotes the engine's number.

## Decisions / surprises

All promoted to `docs/decisions.md` 2026-08-02.

**The thing worth remembering: the interesting assertion is the number, not the prose.**
It is easy to write a test that checks the agent said "wardrobe" — and that test passes for a
model that names the object and then invents a plausible-sounding "move it about a foot." So
both the scripted test and the live case assert that the distance in the model's
recommendation is the distance in the trace. That is the only assertion that actually defends
the division of labor, because it fails the exact case where the writing is good and the
engineering is fake.

The same reasoning is why the tool carries the engine's `detail` string: the model should be
re-wording a measured sentence, not composing one from loose fields.

**Surprise 1 — the `.env` in the tracker stamp is not a repo fact.** The 2026-07-24 stamp
reads "Live suites run with the key now in repo-root `.env` (gitignored)," which I took to
mean live suites were runnable here. There is no `.env` in this clone and no
`ANTHROPIC_API_KEY` in the environment — of course there isn't, gitignored means exactly
that. This is the 2026-07-27 stale-clone lesson wearing a new hat: a tracker line describing
one machine's local state reads like a property of the project. Reworded the stamp so the
next person doesn't lose the same ten minutes.

**Surprise 2 — the system `python3` here is 3.9 and can't import pydantic.** The project env
is `backend/.venv` (3.13). Every validation command in `workflows.md` says `python3`, which
silently means "the wrong interpreter" on this machine. Added a heads-up line to `TODO.md`;
the commands themselves are P1's to change if we want them portable.

**Surprise 3 — the TODO gate table was two sessions stale.** It read 248 backend tests; the
2026-07-30 merge had moved it to 252 without refreshing the table. Fixed, and I kept the old
stamp underneath rather than overwriting it, so the drift is visible rather than erased.

## Questions for teammates

- **@Anish** — can you run `pytest backend/tests/test_agent_live.py -m live` on the machine
  with the key? The bungalow-blocked case writes its golden and `pytest.skip`s for review on
  first run. I'd like a second pair of eyes on whether the model's phrasing of "move the
  wardrobe 0.85 m" reads as advice a person would act on, or as a robot reciting a
  measurement — that's a judgment call I can't make from a green test.
- **@Anish** — the severity mapping (`blocks_opening` on a sleeping room's only way out =
  high, otherwise med; `narrows_route` = low) is mine and it is arguable. It lives in the
  prompt precisely so it can be argued with. If you disagree, that's a prompt edit, not a
  code change.

## Next steps

1. Run the live agent suite on a machine with the key; review and commit
   `backend/tests/golden/agent_bungalow_blocked.json`.
2. Unchanged and still the largest open non-hardware item: `/score`'s un-analysed-home
   scoring question (`TODO.md` → Backend), which needs P1's call, not more code.
3. Also still open from the 2026-07-30 merge: nobody has booted the merged app on a simulator
   and looked at it. I did not do that this session — this was a backend-only change.
