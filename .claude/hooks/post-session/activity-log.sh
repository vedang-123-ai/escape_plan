#!/usr/bin/env bash
# Activity log. Wired via Stop in .claude/settings.json.
#
# Appends one entry to docs/tracker/activity-log.md whenever a session actually changed files.
# Machine-written on purpose: the previous convention relied on a human remembering to log,
# and it decayed — the tracker ended up contradicting itself in nine places. A hook cannot
# forget.
#
# Read-only turns (questions, searches, reviews) change nothing and write nothing, so the log
# stays signal rather than noise.
set -uo pipefail

cd "${CLAUDE_PROJECT_DIR:-.}" || exit 0
git rev-parse --git-dir >/dev/null 2>&1 || exit 0

LOG="docs/tracker/activity-log.md"

# Working-tree changes plus anything committed in the last few minutes: a session that
# committed its own work leaves a clean tree, and that is exactly the session worth logging.
dirty=$(git status --porcelain 2>/dev/null)
recent=$(git log --since="45 minutes ago" --pretty=format:'%h %s' 2>/dev/null)
[ -z "$dirty" ] && [ -z "$recent" ] && exit 0

stamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
sha=$(git rev-parse --short HEAD 2>/dev/null || echo "no-commit")
branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "?")
who=$(git config user.name 2>/dev/null || echo "unknown")

if [ ! -f "$LOG" ]; then
  mkdir -p "$(dirname "$LOG")"
  {
    echo "# Activity log"
    echo
    echo "_Append-only and machine-written by \`.claude/hooks/post-session/activity-log.sh\`."
    echo "Do not edit by hand — if something here is wrong, fix the hook._"
    echo
    echo "Open work lives in \`TODO.md\`. This file is the record of what actually happened."
    echo
  } > "$LOG"
fi

# Bounded: a huge refactor should not paste 400 paths into the log.
changed_count=$(printf '%s\n' "$dirty" | grep -c . || true)
changed_list=$(printf '%s\n' "$dirty" | sed 's/^ *//' | head -25 | sed 's/^/  - /')
[ "$changed_count" -gt 25 ] && changed_list="${changed_list}
  - …and $((changed_count - 25)) more"

{
  echo "## $stamp · $who · \`$branch\` @ \`$sha\`"
  echo
  if [ -n "$recent" ]; then
    echo "**Commits this session**"
    printf '%s\n' "$recent" | sed 's/^/  - /'
    echo
  fi
  if [ -n "$dirty" ]; then
    echo "**Uncommitted working-tree changes ($changed_count)**"
    printf '%s\n' "$changed_list"
    echo
  fi
} >> "$LOG"

exit 0
