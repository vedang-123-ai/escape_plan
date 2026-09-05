# S6 arc — readiness pivot scoping (no code)

- **Who:** P1 (Anish) + Claude
- **Date(s):** 2026-09-05
- **Status when I stopped:** nine long-horizon session prompts written and filed; **zero code
  written, zero schema touched, pivot NOT approved.** The first action item is the decision itself.

## What happened

Session started as "launch the app" — built and ran on the booted iPhone 17 Pro sim
(`.build-run`, `cac.Escape-Plan`, PID 9860). It launched fine: House screen, dollhouse rendering,
`/routes` in flight showing the cold-start notice. Confirmed **`escape_plan/BackendConfig.local.json`
is still missing** on this machine, exactly as START-HERE §2 warns — so backend calls 401 until the
token is added. Nothing was fixed there; the file is gitignored and needs the real token.

Then the session turned into a product argument, which is the actual output. The premise
("aren't the routes naive? the owner already knows their house") was pressed, and it mostly holds
for an able-bodied adult. The counter-example is already ours: the `mobility_limited` upstairs
sleeper on `twostory.json` getting `no_viable_route`. That is the app telling someone something
they genuinely do not know, and it is currently buried under a generic escape-route pitch.

Grilled the pivot at high intensity (13 decisions, four batches), then wrote it up as a playbook
arc: `docs/playbook/06-pivot-intro.md` + `S6-1.md`…`S6-9.md`, one paste-ready prompt per feature,
each self-contained because the session running it will not have this conversation in context.

## Decisions / surprises

- **The biggest surprise was how much already exists.** `backend/app/scoring/checklist.py` is
  already a deterministic checklist generator with stable ids and persisted done-state, and
  `ScoreScreen` already renders it with toggles. The pivot's centrepiece is largely a *promotion*
  of existing machinery to the Home tab, not new machinery. The prompts say so loudly, because the
  default failure mode here is a session rebuilding a parallel checklist.
- **`routing/hazard.py` already means fire-spread simulation.** Multi-peril work is namespaced
  `routing/perils/` to avoid overloading the word. Would have been a nasty collision.
- **The interview must run with no network.** The AI account is dry; a front door that needs a live
  call would be dead on first launch. Scripted copy, model phrasing only ever as a layer on top.
- All 13 locked decisions are recorded in `docs/decisions.md` and repeated in `06-pivot-intro.md`
  so a session cannot miss them.
- **Deliberately not decided:** whether to actually do this. See below.

## Questions for teammates

- @P1 — **the real question is pivot vs. finish.** The S6 arc is nine sessions of new scope while
  `docs/START-HERE.md` still has an open handoff whose gap is device feel, not code, and Oct 24
  has not moved. My read: the *reframe* (lead with findings and the accessibility case rather than
  animated routes) is worth taking almost for free and mostly costs copy; the *three-peril engine
  rebuild* is the expensive half. Those two can be separated — S6.2/S6.3 are where the cost is.
- @P1 — the backend bearer token for `BackendConfig.local.json` is still needed for any real
  device testing, pivot or not.

## Next steps

1. Answer pivot-or-finish. Nothing in S6 starts before that.
2. If finishing the current app: go back to `docs/START-HERE.md` §3a — camera feel on a physical
   phone — and leave the S6 files as a filed proposal.
3. If pivoting: S6.1 and S6.2 are the only two that can start immediately, and S6.2 (corpus) is
   independent of everything else, so it parallelizes cleanly.
