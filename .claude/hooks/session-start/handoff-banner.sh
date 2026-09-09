#!/usr/bin/env bash
# SessionStart — points every session at the blocker board.
#
# Why a hook and not just CLAUDE.md: this is status, and status goes stale. CLAUDE.md carries the
# durable rules; this carries "here is where we actually are today" and is cheap to change.
#
# Deliberately short. It used to inject a 45-line recital that every session had to repeat back
# verbatim, which cost more context than it saved (see docs/decisions.md, 2026-09-08). The traps
# it used to list — dry Anthropic account, SourceKit, iOS flake — live in CLAUDE.md now, which
# already loads every session, so repeating them here was pure duplication.
#
# Kill switch: set `handoff_status: closed` in the front-matter of docs/START-HERE.md.
# That is the intended way to turn this off. Deleting the hook to silence it is not.
set -euo pipefail

ROOT="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
BRIEF="$ROOT/docs/START-HERE.md"

[ -f "$BRIEF" ] || exit 0

# Front-matter only (first 10 lines) so a `closed` mentioned in the prose can't re-arm it.
head -10 "$BRIEF" | grep -qi '^handoff_status:[[:space:]]*active' || exit 0

OWNER="$(head -10 "$BRIEF" | sed -n 's/^handoff_owner:[[:space:]]*//p' | head -1)"
OWNER="${OWNER:-the project owner}"

read -r -d '' CONTEXT <<EOF || true
OPEN HANDOFF from ${OWNER}. The engineering is done; the remaining work is device-gated —
camera feel, frame rate and the golden path have never been touched on a physical iPhone.

Before proposing any plan, read docs/tracker/BLOCKERS.md (the ranked board of everything
blocking or unverified). docs/START-HERE.md has the long-form brief on the device pass.

If the user asked for something unrelated, just help them with that — don't redirect them.
EOF

python3 - "$CONTEXT" <<'PY'
import json, sys
print(json.dumps({
    "hookSpecificOutput": {
        "hookEventName": "SessionStart",
        "additionalContext": sys.argv[1],
    }
}))
PY
