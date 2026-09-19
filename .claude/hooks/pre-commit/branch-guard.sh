#!/usr/bin/env bash
# Branch guard. Wired via PreToolUse(Bash) in .claude/settings.json.
# Three people work in parallel, one branch per playbook session (s11-N-slug). A direct commit on
# `main` is how the last fork happened, so `git commit` on main is blocked. Merging to main uses
# `git merge --no-ff`, which is not affected. Finishing a merge that stopped for conflicts
# (MERGE_HEAD present) is allowed. Escape hatch: put ALLOW_MAIN_COMMIT=1 in the command.
set -uo pipefail

input=$(cat)
cmd=$(printf '%s' "$input" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("tool_input",{}).get("command",""))' 2>/dev/null)

case "$cmd" in
  *"git commit"*) ;;
  *) exit 0 ;;
esac
case "$cmd" in
  *ALLOW_MAIN_COMMIT=1*) exit 0 ;;
esac

branch=$(git branch --show-current 2>/dev/null || true)
[ "$branch" = "main" ] || exit 0

if git rev-parse -q --verify MERGE_HEAD >/dev/null 2>&1; then
  exit 0
fi

echo "BLOCKED: you are on 'main'. Work on a session branch: git switch -c s11-N-slug origin/main (see docs/playbook/README.md, Branch protocol). To merge finished work use: git switch main && git merge --no-ff <branch>." >&2
exit 2
