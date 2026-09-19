#!/usr/bin/env bash
# SessionStart — surfaces the FIRST-PRIORITY gate, then points at the blocker board.
#
# Why a hook and not just CLAUDE.md: this is status, and status goes stale. CLAUDE.md carries the
# durable rules; this carries "here is where we actually are today" and is cheap to change.
#
# Deliberately short. It used to inject a 45-line recital that every session had to repeat back
# verbatim, which cost more context than it saved (see docs/decisions.md, 2026-09-08). The traps
# it used to list — dry Anthropic account, SourceKit, iOS flake — live in CLAUDE.md now, which
# already loads every session, so repeating them here was pure duplication.
#
# Two independent switches, on purpose:
#   * handoff banner — `handoff_status: closed` in docs/START-HERE.md front-matter.
#   * FIRST-PRIORITY gate — `gate_status: closed` in docs/tracker/FIRST-PRIORITY.md.
# Closing the handoff must NOT silence the gate, so the gate is computed first and emitted
# on every exit path. Deleting either file to silence it is not the intended way.
set -euo pipefail

emit_context() {
  python3 - "$1" <<'PY'
import json, sys
print(json.dumps({
    "hookSpecificOutput": {
        "hookEventName": "SessionStart",
        "additionalContext": sys.argv[1],
    }
}))
PY
}

ROOT="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
BRIEF="$ROOT/docs/START-HERE.md"
GATE="$ROOT/docs/tracker/FIRST-PRIORITY.md"

# The gate leads, and is deliberately INDEPENDENT of the handoff kill switch below:
# closing the handoff must not silence an unverified build.
GATE_TEXT=""
if [ -f "$GATE" ] && head -5 "$GATE" | grep -qi '^gate_status:[[:space:]]*open'; then
  GATE_OWNER="$(head -5 "$GATE" | sed -n 's/^gate_owner:[[:space:]]*//p' | head -1)"
  GATE_TEXT="FIRST PRIORITY${GATE_OWNER:+ (${GATE_OWNER})} — BEFORE ANY OTHER WORK.
Four bodies of Swift have landed since the last verified iOS run (615 passed, 2026-09-09)
and none has a recorded result. Someone with a working simulator must run the iOS suite
and record the real count from the result bundle (NOT the console, which undercounts).

Read docs/tracker/FIRST-PRIORITY.md — it has the command, the two defects to fix after,
and how to clear this gate. Do not start new feature work, or S8.2, ahead of it.

"
fi

# The handoff brief is optional; the gate above stands on its own.
if [ ! -f "$BRIEF" ]; then
  [ -n "$GATE_TEXT" ] && emit_context "$GATE_TEXT"
  exit 0
fi

# Front-matter only (first 10 lines) so a `closed` mentioned in the prose can't re-arm it.
if ! head -10 "$BRIEF" | grep -qi '^handoff_status:[[:space:]]*active'; then
  [ -n "$GATE_TEXT" ] && emit_context "$GATE_TEXT"
  exit 0
fi

OWNER="$(head -10 "$BRIEF" | sed -n 's/^handoff_owner:[[:space:]]*//p' | head -1)"
OWNER="${OWNER:-the project owner}"

read -r -d '' CONTEXT <<EOF || true
OPEN HANDOFF from ${OWNER}. The remaining work is device-gated — camera feel, frame rate
and the golden path have never been touched on a physical iPhone, and the S9 AR arc has
never been verified on one either.

Before proposing any plan, read docs/tracker/BLOCKERS.md (the ranked board of everything
blocking or unverified). docs/START-HERE.md has the long-form brief on the device pass.

If the user asked for something unrelated, just help them with that — don't redirect them.
EOF

emit_context "${GATE_TEXT}${CONTEXT}"
