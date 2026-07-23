#!/usr/bin/env bash
# Tracker drift warning. Wired via PreToolUse(Bash) in .claude/settings.json.
#
# Warns — never blocks — when a commit touches code but not the tracker. Deliberately toothless:
# the activity-log Stop hook already records what changed automatically, so this is a nudge to
# update the *interpretation* (TODO.md), not a gate. Blocking commits over documentation is how
# people learn to pass --no-verify reflexively.
set -uo pipefail

input=$(cat)
cmd=$(printf '%s' "$input" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("tool_input",{}).get("command",""))' 2>/dev/null)

case "$cmd" in
  *"git commit"*) ;;
  *) exit 0 ;;
esac

staged=$(git diff --cached --name-only 2>/dev/null)
[ -z "$staged" ] && exit 0

touches_code=$(printf '%s\n' "$staged" | grep -cE '^(backend/|escape_plan/|escape_planTests/|tools/|schema/)' || true)
touches_tracker=$(printf '%s\n' "$staged" | grep -cE '^docs/tracker/' || true)

if [ "$touches_code" -gt 0 ] && [ "$touches_tracker" -eq 0 ]; then
  echo "NOTE: this commit changes $touches_code code file(s) but nothing in docs/tracker/." >&2
  echo "      If it finished or discovered work, update docs/tracker/TODO.md — that file is" >&2
  echo "      only trustworthy because it gets updated at the moment the work happens." >&2
  echo "      (Not blocking. Ignore freely for typos and mechanical fixes.)" >&2
fi

exit 0
