# commands/

Slash commands. Most are thin wrappers that delegate to a skill or an agent — the logic lives
there, so it stays invocable both ways.

| Command | Does |
|---|---|
| `/session S11.<n>` | Runs a playbook session end to end: branch, prereq gate, plan, execute, acceptance, handoff |
| `/handoff <id>` | The end-of-session protocol alone (→ `end-of-session-handoff` skill) |
| `/verify` | Full green gate (→ `verify-all` skill) |
| `/verify-docs` | Audits docs against the real repo (→ `doc-auditor` agent) |
| `/tracker` | Read-only status summary from `docs/tracker/BLOCKERS.md`, `TODO.md` and `origin/main` |
| `/lanes` | Plan, launch, and integrate parallel worktree sessions (→ `parallel-lanes`) |
| `/validate-corpus` | Runs `backend/corpus/validate.py` and fixes failures |

`_TEMPLATE.md` is the scaffold — copy it, don't invoke it.
