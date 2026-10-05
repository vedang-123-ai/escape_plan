#!/usr/bin/env bash
# Remove local, regenerable build output: xcodebuild derived data, logs and .xcresult bundles in the repo root,
# the .build/logs folder, and the pytest cache. Everything here is gitignored. Keeps .build/ (SwiftPM cache) and
# .venv/ (backend env) unless you pass --all.
set -euo pipefail
cd "$(dirname "$0")/.."

for pid in $(pgrep -x xcodebuild || true); do
  echo "xcodebuild is running (pid $pid); finish or stop it first." >&2
  exit 1
done

rm -rf .build-* .build/logs .pytest_cache backend/.pytest_cache
if [ "${1:-}" = "--all" ]; then
  rm -rf .build .venv backend/.venv artifacts
fi
echo "cleaned"; df -h . | tail -1
