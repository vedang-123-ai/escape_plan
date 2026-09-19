/verify-docs

Audit the documentation against the repository that actually exists, and report drift.

Delegate to the `doc-auditor` agent. It is read-only — it reports, it does not fix. Bring
anything it finds back here and fix it explicitly, so the fix is visible in the diff.

Scope, unless the user narrows it:

- `docs/tracker/BLOCKERS.md` and `docs/tracker/TODO.md` — the source of truth for open work. Its `_Last verified:_` stamp,
  its test-count table, and every path it names.
- `CLAUDE.md`, `backend/CLAUDE.md`, `escape_plan/CLAUDE.md`, `README.md`.
- `.claude/` — rule `globs` that match nothing, index READMEs that disagree with what's on
  disk, skills or commands quoting paths and commands that no longer exist.
- `docs/decisions.md` and `docs/tools-used.md` — dependencies listed vs. actually installed.

Not in scope: `docs/tracker/notes/` and `docs/tracker/activity-log.md`. Both are append-only
history. They record what was true when written; that is not drift, and rewriting them would
destroy the record.

Run this before a handoff, after integrating parallel work, and whenever a doc's claims feel
like they might have rotted. `/verify` checks that the code is green; this checks that the
docs are honest.
