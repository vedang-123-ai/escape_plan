# hooks/

Lifecycle scripts that fire automatically. The folders are conceptual phases; the actual
wiring lives in `.claude/settings.json` under `hooks` — a script here that isn't wired there
never runs.

Active hooks:

- `session-start/handoff-banner.sh` — SessionStart. Injects the open team handoff
  (`docs/START-HERE.md`) at the top of every session's context, so a teammate is told what
  they're supposed to be working on before they ask. Self-silencing: it emits nothing once
  that file's front-matter says `handoff_status: closed`. **Close the handoff to turn it off;
  don't delete the hook.** Mirrored as a prose block at the top of the root `CLAUDE.md` so it
  still lands for anyone who hasn't trusted this project's hooks.
- `pre-generation/schema-guard.sh` — PreToolUse(Edit|Write). Forces an explicit user
  confirmation before any modification of an existing `schema/homemodel.schema.json`
  (schema-is-law: version bump + a clean `schema-contract-guardian` run; there is no human
  sign-off). First-time creation (S0.2) is unaffected. **It matches `Edit|Write` only** — a
  `Bash` heredoc or `sed` rewrites the schema with no prompt at all, so this is a reminder
  rather than an enforcement point.
- `pre-commit/secrets-guard.sh` — PreToolUse(Bash) on `git commit`. Blocks commits whose
  staged diff contains Anthropic API key material.

Conventions: scripts read the tool-call JSON on stdin; exit 2 + stderr blocks, JSON
`permissionDecision: "ask"` prompts the user, exit 0 passes. Keep hooks dependency-free
(bash + python3 stdlib) and fast. `chmod +x` every script and wire it in settings.json.
