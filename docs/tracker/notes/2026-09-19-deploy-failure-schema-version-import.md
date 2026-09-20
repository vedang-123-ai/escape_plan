# Out-of-band — the 2026-09-19 Render deploy failure

- **Who:** P3
- **Date(s):** 2026-09-19
- **Status when I stopped:** fixed and green locally on `fix-schema-version-import` (backend 556 passed,
  1 skipped, 13 deselected); the Render redeploy itself is still unverified.

## What happened

Started from "check the failed deployment on GitHub history". First thing worth knowing: **there is no
`.github/workflows/` in this repo.** What shows up as deployment history on GitHub is the Render GitHub App
posting deployment statuses. Deployment `6537170320` on `main - escape-plan-backend`, commit `d6e982c`,
went `in_progress` 2026-09-19 04:40 UTC and `failure` at 04:41 — 73 seconds, too fast to be a build.

It was an import error, reproducible in one line:

```
cd backend && .venv/bin/python -c "import app.main"
ImportError: cannot import name 'SCHEMA_VERSION' from 'app.models'
```

`backend/app/builder/actions.py:26` imported it; nothing has ever defined it on `main`. `grep -rn
SCHEMA_VERSION backend/` returned exactly two hits, both in that one file. `uvicorn app.main:app` therefore
never bound a port, so Render failed the deploy. The backend suite was not 556 passed — it was **13
collection errors**, every module that reaches `app.main` or `app.builder`.

### The cause, which is the part worth remembering

`d6e982c` is `Merge remote-tracking branch 'origin/s6-1-schema-2-0'`. Its two parents:

| parent | `models.py` | `actions.py` |
| --- | --- | --- |
| `d53cf4c` (main side) | schema **2.1**, no `SCHEMA_VERSION` | imports `EXTERIOR_ID, HomeModel` |
| `933f233` (the branch) | defines `SCHEMA_VERSION = "2.0"` | imports `EXTERIOR_ID, SCHEMA_VERSION, HomeModel` |

The merge kept **main's `models.py` byte-for-byte** (right — 2.1 supersedes 2.0) and **the branch's
`actions.py` byte-for-byte** (the hunk that needs the 2.0-era constant). Two different files, so git
reported no conflict and nobody ran the gate before pushing. Verified with `git diff --quiet d53cf4c
d6e982c -- backend/app/models.py` (identical) and the same against `933f233` for `actions.py` (identical).

This is `CLAUDE.md`'s "don't trust a clean merge" trap, second occurrence — the first was the flipped
rotation on 2026-09-18. Both times a clean merge combined two halves that were individually correct.

## Decisions / surprises

- **Fix points at `schema_migrator.CURRENT_VERSION`, not a reinstated `SCHEMA_VERSION`.** `main` already had
  a single source of truth (`app/schema_migrator.py:4`). Defining the second name would have "completed" the
  merge and left the exact duplication that allowed the drift. In `docs/decisions.md`.
- **The branch's actual intent still survives.** It was fixing `new_draft` stamping `"1.1"` forever; drafts
  now come out `"2.1"`.
- **Surprise: prod was never down.** Render keeps the last good deploy live on a failed build, so
  `escape-plan-backend.onrender.com/health` returned 200 the whole time — after a **14 second** free-tier
  cold start. My first `curl -m 25` timed out and looked like an outage; it wasn't. Budget for that cold
  start when filming.
- **Surprise: `new_draft` had no assertion on `schema_version` at all** (`test_builder_actions.py` calls it
  twice and checks neither). Added one that reads the accepted value off `HomeModel`'s `Literal` rather than
  hardcoding `"2.1"`, so the next version bump fails here if only one side moves.

## Questions for teammates

- @P1 / @P2 — **who owns adding CI?** Render deploys every push to `main` and nothing runs the gate first,
  so a non-importing `main` is only caught by the deploy failing. `pytest -m "not live"` plus
  `backend/corpus/validate.py` on push would have caught this in under a minute. Logged in `BLOCKERS.md`,
  unassigned.
- Whoever pushed `d6e982c`: the baseline board's open question "`origin/s6-1-schema-2-0`: archive-tag and
  delete, or merge?" got answered by merging. That line is now closed in `BLOCKERS.md` pointing here.

## Next steps

1. After the merge to `main` is pushed, **watch the Render deployment status on the merge commit and confirm
   `success`** — `gh api repos/vedang-123-ai/escape_plan/deployments --jq '.[0].id'` then
   `.../deployments/<id>/statuses`. Then re-check `/health` (allow ~15s for the cold start). Until that is
   green the deployed backend is still 2026-09-17 code.
2. The three `subagent-*` branches from the baseline board are still unexamined. `d6e982c`'s other parent
   `d53cf4c` merged one of them. Worth a look before the next merge to `main`.
