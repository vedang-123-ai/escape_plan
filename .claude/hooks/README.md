# hooks/

Lifecycle scripts that fire automatically. The folders are conceptual phases; the actual
wiring lives in `.claude/settings.json` under `hooks` — a script here that isn't wired there
never runs.

Active hooks:

- `pre-generation/schema-guard.sh` — PreToolUse(Edit|Write). Forces an explicit user
  confirmation before any modification of an existing `schema/homemodel.schema.json`
  (schema-is-law: version bump + team sign-off required). First-time creation (S0.2) is
  unaffected.
- `pre-commit/secrets-guard.sh` — PreToolUse(Bash) on `git commit`. Blocks commits whose
  staged diff contains Anthropic API key material.

Conventions: scripts read the tool-call JSON on stdin; exit 2 + stderr blocks, JSON
`permissionDecision: "ask"` prompts the user, exit 0 passes. Keep hooks dependency-free
(bash + python3 stdlib) and fast. `chmod +x` every script and wire it in settings.json.
