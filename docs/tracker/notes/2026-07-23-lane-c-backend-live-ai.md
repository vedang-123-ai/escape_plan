# Lane C — backend robustness + live AI unlock (S3.1/S3.2/S3.3/S3.4 live halves, S3.2/S3.5 defects)

- **Who:** Claude (Lane C), key provided by Anish
- **Date(s):** 2026-07-23
- **Status when I stopped:** All local live verification DONE and committed on `lane/backend`
  (3 commits: 71ab619 finding ids + lockstep, 03f51ee sonnet-5 fixes + goldens, f39d9f6
  strict tool + latency bounds; docs commit follows). Render env var is the single open item.

## What happened

- **Defect 1 fixed:** agent findings carry a stable content-derived `id`
  (`app.scoring.findings.finding_id`: sha256 of severity + sorted room_ids + normalized
  finding slug, 12 hex). Stamped server-side in `_validate_findings` (model-provided ids are
  overwritten). `checklist.py` keys `agent_finding.<id>` with positional fallback for id-less
  findings. Old positional checkmarks are orphaned by design — see decisions.md.
- **Defect 2 fixed:** `tests/test_finding_lockstep.py` pins the two hand-synced Finding
  classes to identical names/types/requiredness (documented exception: `evidence` — required
  agent-side, defaulted scoring-side) and pins the extra="forbid"/"ignore" pair. Fails on any
  drift, including new fields.
- **Live battery (all with a real key, all hand-reviewed):**
  - `test_ai_live.py`: 6 passed. Goldens committed (`tests/golden/*.json`) — citations all
    resolve, no invented routes/advice, the no-stairs twostory case honestly reports "no
    route" for the whole upstairs. Red-team jump question → safe deferral + 911 + fire dept.
  - `test_agent_live.py`: 2 passed. `agent_apartment.json`: d_entry single-exit bottleneck
    found (high), plus sill-height window failures — all evidence real `toolu_` ids, dropped
    empty, 39.9s. `agent_twostory.json`: `w_kids` undersized window found with correct IRC
    numbers (med) + mobility-limited upstairs gap (high), 42.0s.
  - Latency: warm `/explain` on twostory, 10 samples, cache HIT every request
    (read=9450, created=0): mean 26.3s, **p95 30.2s — the <6s acceptance is unmet**
    (output-bound ~2k tokens; haiku-4-5 ~18.5s). Recorded, not fudged; team decision needed.
  - Chat smoke via TestClient: smoke-detector Q → cited, house-specific (names rooms, Maya,
    Grandpa); earthquake Q → honest deferral, zero invented advice; "I smell smoke NOW" →
    get-out-then-911 first, profile-aware caveat for Grandpa. Outputs in scratchpad
    (`chat_*.json`) — not committed (transient smoke evidence, summarized here).
  - Profile-aware `/explain` (S3.4 open half): Grandpa run avoids stairs/windows and flags
    the entire upstairs as route-less; Maya run narrates her personal route. Confirmed the
    prose reflects the selected profile.
- **Live-exposed bugs fixed in `app/ai/` (all invisible to scripted tests):**
  1. `temperature` → 400 on claude-sonnet-5 (removed everywhere).
  2. Omitted `thinking` now means adaptive on sonnet-5 → agent 71s vs <60s budget; explicitly
     disabled across the AI layer (agent now ~40s).
  3. With thinking off, the agent fabricated evidence refs (`check_egress:w_kids`);
     tightened schema/prompt instructions + bounded resubmit loop (`MAX_SUBMIT_RETRIES=2`);
     scripted tests cover retry-then-success and retries-exhausted (non-live suite now 207).
  4. A live `/explain` emitted a stray `action_2` field crashing `model_validate` → tool is
     now `strict: true` + ValidationError retry branch (10/10 clean after).

## Decisions / surprises

- All promoted to `docs/decisions.md` (3 rows, 2026-07-23): stable-id scheme + orphaned-key
  migration story; the sonnet-5 API adaptations; the honest p95 miss + test-bound change.
- Surprise: one transient garbled generation (95s, corrupted prose that still passed citation
  validation) — retried clean. Tracked in TODO.
- Surprise: `pytest backend/tests/` does NOT include live tests (pytest.ini addopts) — the
  full-including-live gate is `-m ""`. Live latency bounds can flake on API variance.
- S3.1 explain goldens were captured before the thinking-disabled change; asserts are
  structural and pass under the final config (verified via re-run).

## Questions for teammates

- @Anish: set `ANTHROPIC_API_KEY` on Render (dashboard → escape-plan-backend → Environment →
  add → save/redeploy), then say so — verification steps are in TODO.md (S1.6 item).
- @team: pick a lever for the p95 `/explain` miss (terser output / per-room calls /
  streaming UX / faster model / revised target). Numbers in decisions.md.

## Next steps

1. Render env var + deployed verification (only open lane item; exact steps in TODO.md).
2. iOS TODO(integration): thread the finding `id` through `AgentFinding` and key checklist
   state on `agent_finding.<id>` (TODO.md Backend section).
3. At integration time this lane merges FIRST (touches only backend/ + docs).
