# hooks/

Lifecycle scripts that fire automatically. The folders are conceptual phases; the actual
wiring lives in `.claude/settings.json` under `hooks` — a script here that isn't wired there
never runs.

Active hooks (all wired in `settings.json` unless marked):

- `session-start/handoff-banner.sh` — SessionStart. Injects the open handoff (`docs/START-HERE.md`, the S11 arc) and the
  FIRST-PRIORITY gate (`docs/tracker/FIRST-PRIORITY.md`, cleared by session S11.8) at the top of every session. The two
  are independent switches: `handoff_status: closed` silences the brief, `gate_status: closed` silences the gate. **Close
  them to turn them off; do not delete the hook.** Its message text is owner-editable; see BLOCKERS (S11) for the stale wording.
- `pre-generation/schema-guard.sh` — PreToolUse(Edit|Write). Forces an explicit confirmation before modifying an existing
  `schema/homemodel.schema.json` (schema-is-law: version bump plus a clean `schema-contract-guardian` run; no human
  sign-off). It matches `Edit|Write` only, so a `Bash` heredoc or `sed` bypasses it: a reminder, not enforcement.
- `pre-commit/secrets-guard.sh` — PreToolUse(Bash) on `git commit`. Blocks commits whose staged diff contains Anthropic key material.
- `pre-commit/tracker-warn.sh` — PreToolUse(Bash) on `git commit`. Warns (does not block) when a commit changes code but nothing
  under `docs/tracker/`.
- `post-session/activity-log.sh` — Stop. Appends to `docs/tracker/activity-log.md` when the tree is dirty or there was a recent
  commit. That file merges with `merge=union` so parallel sessions do not conflict.
- `pre-commit/branch-guard.sh` — PreToolUse(Bash) on `git commit`. Blocks a direct commit on `main` (merges and
  conflict-finishing commits are allowed; `ALLOW_MAIN_COMMIT=1` in the command overrides). Wired and made executable
  2026-09-25 (audit remediation). It reads the branch of the hook's working directory, so a `cd other-worktree && git
  commit` is judged by the session's checkout, not the worktree's: a reminder in that case, not enforcement.

Conventions: scripts read the tool-call JSON on stdin; exit 2 + stderr blocks, JSON
`permissionDecision: "ask"` prompts the user, exit 0 passes. Keep hooks dependency-free
(bash + python3 stdlib) and fast. `chmod +x` every script and wire it in settings.json.
