#!/usr/bin/env bash
# Smoke-check the deployed backend: is it up, and is it running main's HEAD?
#
#   bash scripts/smoke-deploy.sh [base-url]
#
# Waits out the Render free-tier cold start (about 50 s), checks GET /health answers 200,
# reads the `commit` field /health reports (S11.31, from RENDER_GIT_COMMIT) and compares it
# with origin/main's HEAD (read with `git ls-remote`, which changes nothing locally).
# It reads no secrets and sends no token: /health is public.
#
# Exit codes, so a caller can tell the outcomes apart:
#   0  live is up and running origin/main HEAD
#   1  live did not answer 200 within the wait (down, or still cold-starting)
#   2  live is up but behind main. Normal for a few minutes after a merge: Render deploys
#      only after the gate workflow's checks pass (render.yaml autoDeployTrigger: checksPass)
#   3  live is up but reports no usable commit (RENDER_GIT_COMMIT unset, or a non-Render host)
#   4  could not read origin/main HEAD (no network to GitHub, or not in the repo)
#
# Environment overrides:
#   SMOKE_URL             base URL (default the Render service; an argument wins)
#   SMOKE_TIMEOUT         seconds to wait for a 200 (default 120)
#   SMOKE_EXPECT_COMMIT   compare against this sha instead of origin/main HEAD. A test hook:
#                         feed a wrong sha to prove the comparison can fail.
set -uo pipefail

url="${1:-${SMOKE_URL:-https://escape-plan-backend.onrender.com}}"
url="${url%/}"
timeout="${SMOKE_TIMEOUT:-120}"

if [ -n "${SMOKE_EXPECT_COMMIT:-}" ]; then
  expected="$SMOKE_EXPECT_COMMIT"
  expected_from="SMOKE_EXPECT_COMMIT"
else
  expected="$(git ls-remote origin refs/heads/main 2>/dev/null | awk '{print $1}')"
  expected_from="origin/main"
  if [ -z "$expected" ]; then
    echo "FAIL: could not read origin/main HEAD with git ls-remote (offline, or not inside the repo)."
    exit 4
  fi
fi

echo "Checking $url/health (waiting up to ${timeout}s for a cold start)..."
start=$(date +%s)
body=""
code=""
while :; do
  # 30 s per attempt: a cold start holds the first request open rather than refusing it.
  body="$(curl -s -m 30 -w $'\n%{http_code}' "$url/health" 2>/dev/null)"
  code="${body##*$'\n'}"
  body="${body%$'\n'*}"
  [ "$code" = "200" ] && break
  elapsed=$(( $(date +%s) - start ))
  if [ "$elapsed" -ge "$timeout" ]; then
    echo "FAIL: /health did not answer 200 within ${timeout}s (last status: ${code:-no response})."
    echo "      The service is down or still waking. Raise SMOKE_TIMEOUT or check the Render dashboard."
    exit 1
  fi
  echo "  not up yet (status ${code:-no response}, ${elapsed}s elapsed), retrying in 5s..."
  sleep 5
done
echo "OK: /health answered 200 after $(( $(date +%s) - start ))s."

live="$(printf '%s' "$body" | python3 -c 'import json,sys
try:
    print(json.load(sys.stdin).get("commit") or "")
except Exception:
    print("")')"

if [ -z "$live" ] || [ "$live" = "unknown" ]; then
  echo "FAIL: /health reports no commit (got '${live:-nothing}'). RENDER_GIT_COMMIT is unset on this host."
  exit 3
fi

echo "Live commit:     $live"
echo "Expected commit: $expected ($expected_from)"

# Render reports the full sha; accept a prefix match either way so a short sha works too.
case "$expected" in "$live"*) match=1 ;; *) case "$live" in "$expected"*) match=1 ;; *) match=0 ;; esac ;; esac

if [ "$match" = 1 ]; then
  echo "PASS: the live backend is running $expected_from HEAD."
  exit 0
fi

echo "BEHIND: the live backend is up but is NOT running $expected_from HEAD."
echo "        Right after a merge this is expected: Render waits for the gate checks to pass,"
echo "        then builds (several minutes). If it persists, a check failed or the deploy did:"
echo "        see the commit's checks on GitHub and the Events tab in the Render dashboard."
exit 2
