# docs/tracker/

Three state files with deliberately opposite jobs, plus field guides for work that can't be
done at a desk.

| File | What it is | Who touches it |
|---|---|---|
| `TODO.md` | **The** source of truth for open work: everything not yet done, grouped by area, each line naming its next action | Anyone finishing work removes what they finished and adds what they discovered |
| `activity-log.md` | Append-only and **machine-written** — a Stop hook adds an entry whenever a session changes files | Nobody by hand; the hook owns it |
| `notes/` | Append-only session notes, one per work session (copy `_TEMPLATE.md`) — the "why we did it this way" record and the project's process evidence | Whoever ran the session, at the end |
| `field-test-*.md` | Runbooks for acceptance that needs hardware the dev machine doesn't have — procedure, triage loop, and the exact acceptance lines each step closes | Whoever writes one; revised after the trip with what actually happened |

Today there is one field guide: [`field-test-lidar.md`](field-test-lidar.md), which covers the
device trip that closes S1.4 and S1.5. It exists because the scan converter was written
against an *assumed* RoomPlan format and only real exports can falsify that.

`TODO.md` shrinks as work lands. `activity-log.md` and `notes/` only ever grow. That asymmetry
is the point: a list of open work that grows forever stops being read, and a history that gets
edited stops being trustworthy.

## Working here

1. **Starting work?** Open `BLOCKERS.md`, then the session you are running in `docs/playbook/S11-<n>.md`
   (via `/session S11.<n>`). Its BRANCH block tells you which branch to work on.
2. **While working**, jot anything worth remembering into a note — copy `notes/_TEMPLATE.md` to
   `notes/<YYYY-MM-DD>-<slug>.md`. Fragments are fine; it's a lab notebook, not documentation.
3. **Finishing work?** Remove the lines you actually completed, and only those. Add whatever you
   discovered, each with a concrete next action. Then write the session note.
4. Update the `_Last verified:_` stamp at the top of `TODO.md` when you reconcile it against a
   real run, and run `/verify-docs` to check nothing else drifted.

**Removing a line you didn't personally verify is the failure mode this file exists to prevent.**
"The code exists" is not verification. If something needs a device or a real API key you don't
have, leave it there and say so — that honesty is what makes the rest of the file trustworthy.

## Conventions

- Dates are absolute (`2026-07-22`), never "yesterday".
- **Acceptance evidence**: `artifacts/` is gitignored (bulk output — logs, xcresult bundles,
  recordings), so evidence that backs an acceptance claim goes in `docs/evidence/` instead — a
  SMALL curated subset (screenshots <1 MB each, no videos over ~10 MB), one subdirectory per
  session, each referenced from a session note or pairing doc. See `docs/evidence/README.md`.
- Overlap with `docs/decisions.md` is fine: `decisions.md` is the formal deviation log, `notes/`
  is the informal scratchpad. Note it here first, promote real deviations at session end.
- Claude Code reads this folder too — keeping it current means any session can be picked up by
  anyone with zero re-explaining.

Run `/tracker` for a read-only status summary, `/handoff <id>` for the full end-of-session
protocol, and `/verify-docs` to audit these docs against the actual repo.
