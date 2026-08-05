# S1.4/S1.5/S5.2 — field-test guide + scan triage + demo preflight

- **Who:** P3 (Claude Code)
- **Date(s):** 2026-08-05 (same day as the White Model dollhouse overhaul, separate session)
- **Status when I stopped:** Tooling written and exercised. **Nothing acceptance-closing
  happened** — all three artifacts exist to make someone else's device trip and filming day
  cheap. No S1.4/S1.5 criterion moved; they still need hardware.

## What happened

The question was "what can be done while the blockers are someone else's to unblock?" Almost
everything left on the critical path is a human action (top up Anthropic, set a Render env
var, borrow a LiDAR phone) or needs hardware. So: de-risk the two events that will happen
once those unblock, rather than write code nobody asked for.

Three artifacts, all new files, no existing source touched:

### `docs/tracker/field-test-lidar.md`

A runbook for the device trip that closes S1.4 + S1.5. Hardware gate, desk pre-flight,
capture technique, the triage loop, a symptom→cause table, and a table mapping each step to
the acceptance line it closes.

The framing that mattered: the converter's README says outright it was built against an
**assumed** RoomPlan encoding and validated only on synthetic fixtures — and those fixtures
are generated from the same assumptions (`backend/scripts/gen_scan_fixtures.py`), so they
**cannot falsify the converter**. They agree with it by construction. The guide therefore
front-loads "do the format assumptions hold?" ahead of "did conversion succeed?", because the
worst failure mode converts cleanly.

### `backend/scripts/triage_scan.py`

Makes that checkable. Point it at a real `raw.roomplan.json`; it reports input shape, format
assumptions, the converted model room-by-room, acceptance signals (≥1 exterior door, ≥1
window, interior doors paired), idempotency, and JSON Schema + pydantic validation. Exit
0/1/2.

The check I care about most is **transform majorness**. A rigid 4×4 has one row or column of
(0,0,0,1); column-major flattening (what the converter assumes Swift's `JSONEncoder` does to
`simd_float4x4`) puts it at indices 3/7/11/15, row-major at 12/13/14/15. Get it backwards and
nothing raises — every wall direction is wrong, every room falls back to its bounding box, and
the output still passes both validators. That is a silent-wrong-answer bug you would otherwise
find by squinting at a render.

Verified against all four synthetic fixtures: the three clean ones exit 0, `synthetic-messy`
exits 1 with exactly the warnings it should (single-room export, no `sections` labels, room at
confidence 0.38, one opening flagged at ≤0.25).

### `scripts/demo-preflight.py`

Checks the deployed backend is demo-ready, in the app's own terms. Every failure it looks for
has already happened here at least once: missing `BackendConfig.local.json`, missing Render
`ANTHROPIC_API_KEY`, dry Anthropic account, free-tier cold start.

Exercised end-to-end against both the deployed service and a local backend on :8077.

## Decisions / surprises

Nothing deviates from a playbook default, so **`decisions.md` gets no entry**. No new
dependency either, so `tools-used.md` is unchanged — `certifi` is imported optionally and is
already present transitively via the Anthropic SDK.

**Surprise 1 — the deployed backend is healthy and warm.** `/health` answered in 0.6 s, not
the ~50 s a slept free-tier service takes. Worth knowing before anyone budgets for a cold
start on filming day.

**Surprise 2 — `CERTIFICATE_VERIFY_FAILED` against a perfectly healthy backend.** python.org
builds on macOS ship without a usable trust store unless `Install Certificates.command` has
been run, so the first preflight run reported the backend as down when it wasn't. The script
now uses `certifi` when available and, when a cert error does occur, says explicitly that the
problem is on this machine and that the iPhone is unaffected. A preflight tool that cries wolf
is worse than none.

**Surprise 3 — the credits are still out**, re-confirmed today: `/explain` → 502 `Your credit
balance is too low`. The 502/503 split shipped 2026-08-04 is working exactly as intended — the
failure names itself instead of hiding inside a generic 500. This remains the single biggest
open item; the deterministic half (`/routes` 4/4 rooms routed, `/score` 75) is untouched by
it, which is the architecture doing its job.

## Questions for teammates

- @Anish — is there a LiDAR-capable device (iPhone 12 Pro+ or iPad Pro 2020+) available at
  all? Every open S1.4/S1.5 line depends on the answer and nothing else gates them.
- @Anish — the shared bearer token isn't on this machine. It's needed for the in-app half of
  the field test (Part 5) and for filming.

## Next steps

1. Top up Anthropic, then re-run `python3 scripts/demo-preflight.py` — it should reach
   "Ready to film."
2. Set `ANTHROPIC_API_KEY` in the Render dashboard and re-run the preflight against the
   deployed URL (the local `.env` proves nothing about production).
3. Then the device trip, following `field-test-lidar.md` top to bottom.

Unrelated but concurrent: an external audit of the whole repo was running while this session
happened. If it lands findings that touch `backend/app/convert/`, re-run `triage_scan.py` on
the synthetic fixtures as a regression check — it validates the contract end-to-end in about
a second.
