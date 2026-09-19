---
name: parallel-lanes
description: Plan, launch, and integrate multiple sessions running in parallel git worktrees. Use when splitting work across several terminals/agents at once, or when the user talks about "worktrees", "parallel lanes", "running many sessions", or integrating several finished lanes. Encodes the 2026-07-22 lesson — verify the worktrees actually exist.
---

# parallel-lanes

Escape Plan runs multiple playbook sessions concurrently. Done right, each lane is isolated in its
own git worktree; done wrong (2026-07-22), five "lanes" all wrote into one working tree — it
happened to survive, but that's luck, not isolation. This skill makes the isolation real and the
integration disciplined.

## Launching lanes

1. **Pick genuinely independent sessions.** Check `docs/playbook/README.md` (lane table and dependency map)
   and `docs/tracker/BLOCKERS.md`. Never start a session whose prereqs aren't DONE.
2. **Assign non-overlapping file ownership** and state each lane's do-not-touch list explicitly in
   its prompt (e.g. "don't touch PlanScreen.swift or Editor/"). Shared files that must be edited by
   more than one lane (`EditAction.swift`, `ContentView.swift`) are the risk — keep changes there
   strictly additive.
3. **Create a real worktree per lane** and VERIFY it:
   ```
   git worktree add ../ep-<slug> -b s11-N-<slug> origin/main   # branch naming: docs/playbook/README.md
   git worktree list        # confirm the entry exists — do not skip this check
   ```
   If you're not creating worktrees, say so out loud — don't let separate agents silently share
   one tree.
4. Brief each lane precisely the first time (goal, acceptance, do-not-touch, end-of-session
   protocol). Don't launch-wait-rebrief.

## Integrating when they finish

Dispatch the `lane-integrator` agent, or do its checklist yourself:
- Merge order: zero-shared-file lanes first, `EditAction.swift` lanes adjacent (rebase the second
  onto the first), the widest-surface lane (PlanScreen/renderer) last.
- Resolve shared-file conflicts by KEEPING BOTH sides' additions — never `-X ours/theirs` on
  `EditAction.swift`. A dropped switch arm = a build break.
- After the merges: `grep -rn "TODO(integration)" escape_plan/` and close any whose blocking lane
  has now landed.
- Run the full gate (`verify-all` skill) once at the end.
- Reconcile the five docs appends (decisions/TODO.md/tools-used) into one coherent state.
- Write ONE integration session note plus confirm each lane wrote its own.
- **Leave every device-only acceptance box unchecked.**
