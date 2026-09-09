# Working protocol

Work is organized into checkpointed sessions S0.1–S5.3 plus the arc sessions S6.x and S7.x
(`docs/playbook/S<x>-<y>.md`), each with
an owner, prerequisites, acceptance criteria, and a handoff artifact. Dependency map:
`docs/playbook/03-sessions-intro.md`.

## Session rules

1. Read `CLAUDE.md`, the session file, and `docs/decisions.md` before starting. `/session <id>`
   does this for you.
2. Never start a session whose prerequisites aren't DONE.
3. A session is DONE only when every acceptance criterion passes.
4. Every session ends with: acceptance verified, `docs/decisions.md` updated (any deviation
   from playbook defaults, with why), `docs/tools-used.md` updated (any new dependency — CAC
   originality requirement), handoff artifact posted, and — MANDATORY — a session note written
   in `docs/tracker/notes/` (copy `_TEMPLATE.md`) plus `docs/tracker/TODO.md` updated. A session without a handoff and a tracker note didn't happen.

## Schedule pressure

Deadline: submit by Oct 24, 2026; end-to-end demo path must work by Oct 5. If behind, cut in
this order: S4.2 drill → S3.3 chat → S3.5 score → camera tour → simplified agent.
Never cut scan → editor → 3D routes → profile switch.

## Validation commands (grow this list as modules land)

Run the whole gate via the `verify-all` skill / `/verify`. Individually:

- Corpus: `python3 backend/corpus/validate.py`
- Backend: `python3 -m pytest backend/tests/ -m "not live"` (drop `-m` filter only when the
  Anthropic key is set)
- Editor core (pure Foundation, macOS, fast — catches non-exhaustive switches):
  `swift test --package-path tools/editorcore`
- iOS app + unit/UI tests (a real iOS 26.5 simulator IS installed — this works now):
  `xcodebuild test -project escape_plan.xcodeproj -scheme escape_plan -destination
  'platform=iOS Simulator,name=iPhone 17 Pro' -derivedDataPath .build-merge CODE_SIGNING_ALLOWED=NO`
  (add `-only-testing:escape_planTests` to skip the slow UI tests while iterating). SourceKit/VS
  Code can't index this project — trust `xcodebuild`, not the editor's phantom errors.
