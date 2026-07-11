#!/usr/bin/env bash
# Secrets guard. Wired via PreToolUse(Bash) in .claude/settings.json.
# The Anthropic API key must live server-side (env var) and never enter git.
# Before any `git commit`, scan the staged diff for Anthropic key material and
# block the commit if found. All other Bash commands pass through instantly.
set -uo pipefail

input=$(cat)
cmd=$(printf '%s' "$input" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("tool_input",{}).get("command",""))' 2>/dev/null)

case "$cmd" in
  *"git commit"*) ;;
  *) exit 0 ;;
esac

staged=$(git diff --cached 2>/dev/null | grep -E '^\+' || true)
if printf '%s' "$staged" | grep -qE 'sk-ant-[A-Za-z0-9_-]{8,}|ANTHROPIC_API_KEY[[:space:]]*[=:][[:space:]]*[A-Za-z0-9_-]{8,}'; then
  echo "BLOCKED: staged changes appear to contain an Anthropic API key (sk-ant-... or ANTHROPIC_API_KEY=<value>). The key lives server-side in an env var only — unstage the secret before committing." >&2
  exit 2
fi
exit 0
