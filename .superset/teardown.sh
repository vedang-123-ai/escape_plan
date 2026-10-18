#!/usr/bin/env bash
# Superset workspace teardown script.
# Runs in the workspace worktree root before a workspace is deleted.
set -euo pipefail

echo "==> Cleaning workspace build artifacts and virtualenvs..."
if [ -x "./scripts/clean.sh" ]; then
  ./scripts/clean.sh --all || rm -rf .build-* .build/logs .pytest_cache backend/.pytest_cache .build .venv backend/.venv artifacts
else
  rm -rf .build-* .build/logs .pytest_cache backend/.pytest_cache .build .venv backend/.venv artifacts
fi
