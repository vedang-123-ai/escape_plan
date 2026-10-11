# Audit brief (shared by all investigators)

Repo root: `/Users/anish/Documents/Congressional App Challenge/Escape-Plan`
Report directory: `audit/2026-10-11_comprehensive/` (an older audit lives in `audit/*.md` — do NOT modify it; you may read it as a
secondary lead but verify independently, it is dated 2026-09-28 and the code has changed since).

## What the app is (verify, don't trust)
"Escape Plan": SwiftUI + SceneKit iOS app (Xcode project `escape_plan.xcodeproj`, ~60k lines Swift, targets `escape_plan`,
`escape_planTests`, `escape_planUITests`, plus SwiftPM `tools/editorcore` which symlinks app files). Python/FastAPI backend in
`backend/` (routing engine, scoring, Claude-backed grounded chat/explain/analyze/build, auth, cloud sync, MongoDB, render.yaml deploy),
curated corpus in `backend/corpus/`, JSON schema in `schema/`, demo homes in `demo-homes/`. Fire/earthquake/severe-weather readiness;
app draws FIRE routes only. Docs claim: not a firefighter tool, prevention/education, opt-in share-with-fire-department snapshot.
Useful docs: `README.md`, `CLAUDE.md`, `docs/tracker/BLOCKERS.md`, `docs/capabilities.md`, `docs/playbook/01-product-spec.md`,
`docs/demo/claims-ledger-v2.md`, `docs/submission/`, `escape_plan/CLAUDE.md`. Docs may be stale or self-contradictory: **verify claims
against source**.
Ignore generated dirs: `.build`, `backend/.venv`, `__pycache__`, `node_modules`, `xcuserdata`.

## HARD RULES
1. **AUDIT ONLY. Never modify, create, or delete any file outside `audit/2026-10-11_comprehensive/`.** No fixes, no refactors, no
   project-setting edits, no git commits/stash/checkout/reset. `git status` currently shows only `docs/tracker/activity-log.md` modified
   (pre-existing, not yours).
2. Build/test output must go OUTSIDE the repo: use `-derivedDataPath /tmp/audit-dd-<yourname>` and `-resultBundlePath /tmp/...`;
   for python use `PYTHONDONTWRITEBYTECODE=1 python -m pytest -p no:cacheprovider`. Do not run `git clean`.
3. **Secrets:** `escape_plan/BackendConfig.local.json` and any `.env` contain credentials. You may note their existence/handling and
   whether they are gitignored / bundled in the app, but NEVER print token values in reports or output. Do not call the live deployed
   backend with credentials or mutate remote data. Unauthenticated read-only GETs of public health endpoints are OK.
4. Do not edit the other agents' reports. Only write your own report file(s) and optional evidence files under `evidence/`.
5. Only ONE agent (13 Testing, 14 Build) may run `xcodebuild`; others read code. Environment note from lead: `xcrun simctl list runtimes`
   shows NO installed iOS simulator runtime (devices are "unavailable, runtime profile not found"); Xcode 27.0 (27A266a). So runtime
   verification may be BLOCKED; document that exactly (command + output) rather than guessing. Never fabricate a result.
6. Do not invent a policy obstacle. If something can't be done, document the limitation and continue.
7. Labels for every conclusion: **Verified at runtime / Verified by automated test / Verified by source inspection / Inferred but not
   verified / Blocked by environment**.
8. Fire-safety claims: verify against authoritative sources (USFA, FEMA, NFPA, Red Cross, local fire agencies, ready.gov, CPSC, NIST, USGS,
   NOAA/NWS) using web tools. Record claim, source, URL, date checked (today = 2026-10-11). Never invent citations.
9. Be exhaustive: read actual source files in full for your domain (not just greps), trace features end to end, cite `path:line`.
   Depth over speed. If you finish in a few minutes, you have not covered enough — look again.

## Finding format (use exactly)
```
## [SEVERITY] Finding title
**Domain:** …  **Location:** path:line / type / screen / journey
**Observed behavior:** …
**Evidence:** code excerpt / output / source
**Expected behavior:** …
**Root cause:** …
**Impact:** …
**Recommended improvement:** …
**Dependencies:** …
**Verification status:** (one of the 5 labels)
**Confidence:** High/Medium/Low   **Effort:** Small/Medium/Large (assumptions)
```
Give each finding an ID `<AgentNo>-NN` (e.g. `A04-03`). Severities: CRITICAL (verified break of core workflow / data integrity / seriously
misleading safety-related behavior), HIGH, MEDIUM, LOW, OBSERVATION. Do not inflate. Do not report theory as confirmed defects. Don't
duplicate root causes across findings — cross-reference instead.

## Report structure (mandatory sections)
1. Executive summary 2. Scope and files inspected 3. Methods and checks performed 4. Findings (with evidence) 5. Positive findings
6. Systemic issues and root causes 7. Unverified assumptions 8. Areas requiring further investigation 9. Recommended priorities.
Reports should be substantial (typically 300+ lines for major domains). If your domain doesn't apply, say so and describe the scope you
inspected. When done, reply with a ≤15-line summary: report path(s), finding counts by severity, top 5 findings, blocked items.

