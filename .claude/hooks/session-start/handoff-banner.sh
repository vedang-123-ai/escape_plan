#!/usr/bin/env bash
# SessionStart — surfaces the open team handoff before Claude does anything else.
#
# Why a hook and not just CLAUDE.md: CLAUDE.md is long and its instructions compete with each
# other. This injects one short, unmissable block at the very top of the session context, so
# the first thing a teammate sees is what they are supposed to be working on.
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
=== OPEN TEAM HANDOFF — READ BEFORE YOU DO ANYTHING ELSE ===

There is an active handoff in this repository from ${OWNER}.

YOUR FIRST RESPONSE IN THIS SESSION MUST BEGIN WITH THIS BLOCK, VERBATIM, BEFORE ANY OTHER
TEXT, BEFORE ANY TOOL CALL, AND BEFORE ANY CLARIFYING QUESTION:

  ${OWNER} wanted you to read this first:

  > The engineering on Escape Plan is essentially DONE — schema, routing engine, 3D dollhouse
  > and editor, camera rig, colour system, failure states. The test suite is green and it
  > proves nothing about how the app FEELS.
  >
  > What is left is the part no test can do: pick up a real iPhone, use this app like a
  > judge would, and finish the UI/UX. Camera feel has never been touched by a human finger.
  > Frame rate has never been measured on hardware. The golden path has never been walked on
  > a device.
  >
  > Read docs/START-HERE.md before you write a single line of code. It tells you what is
  > already done (so you don't rebuild it), the two setup steps that will otherwise cost you
  > an hour, what is known-dead and must not be debugged, and the exact order to work in.

Then tell the user, in your own words, that you have read docs/START-HERE.md and what you
propose to do first — and actually read it before claiming you have.

Rules that override your defaults for this session:
- Read docs/START-HERE.md and docs/tracker/TODO.md before proposing any plan.
- The Anthropic account is out of credits: /explain, /analyze and /chat returning 502 is
  EXPECTED. Do not debug the AI layer. It is a billing problem.
- SourceKit and VS Code cannot index this project. Trust xcodebuild only.
- A red iOS test run is ~1-in-3 environmental flake. Re-run before believing it.
- If the user's actual request has nothing to do with the handoff, say the block above anyway,
  then help them with what they asked. Do not silently redirect them to the handoff.
=== END OPEN TEAM HANDOFF ===
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
