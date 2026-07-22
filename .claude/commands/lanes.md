# /lanes

Plan, launch, or integrate parallel worktree sessions. Invoke the `parallel-lanes` skill.

- **Launching:** pick independent sessions (check `docs/tracker/board.md` + the dependency map),
  assign non-overlapping file ownership with explicit do-not-touch lists, create a real
  `git worktree` per lane and VERIFY it with `git worktree list`, then brief each lane precisely.
- **Integrating:** dispatch the `lane-integrator` agent — collision checks, close cross-lane
  `TODO(integration)`s, run the full gate (`/verify`), reconcile the docs, write one integration
  note. Leave device-only boxes unchecked.

If the argument names finished lanes to integrate, go straight to integration; otherwise help plan
and launch.
