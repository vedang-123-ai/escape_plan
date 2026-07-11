#!/usr/bin/env bash
# Schema-is-law guard. Wired via PreToolUse(Edit|Write) in .claude/settings.json.
# After S0.2 finalizes schema/homemodel.schema.json, any change requires a version
# bump + team sign-off. This hook forces an explicit user confirmation ("ask")
# whenever an EXISTING schema file is about to be modified. Creating the file for
# the first time (S0.2 itself) passes through untouched.
set -uo pipefail

input=$(cat)
file=$(printf '%s' "$input" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("tool_input",{}).get("file_path",""))' 2>/dev/null)

case "$file" in
  */schema/homemodel.schema.json|schema/homemodel.schema.json)
    if [ -f "schema/homemodel.schema.json" ]; then
      printf '%s' '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"ask","permissionDecisionReason":"schema/homemodel.schema.json is THE project contract. Changes require a schema_version bump and team sign-off (see CLAUDE.md). Approve only if that is happening."}}'
    fi
    ;;
esac
exit 0
