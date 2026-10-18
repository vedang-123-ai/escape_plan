#!/usr/bin/env bash
# Superset workspace setup script.
# Runs in the workspace worktree root whenever a new workspace is created.
set -euo pipefail

# Resolve the root repository path cleanly even if SUPERSET_ROOT_PATH contains unquoted spaces in its parent env
ROOT_PATH="${SUPERSET_ROOT_PATH:-}"
if [ -z "$ROOT_PATH" ] || [ ! -d "$ROOT_PATH" ]; then
  ROOT_PATH="$(cd "$(git rev-parse --git-common-dir)/.." && pwd)"
fi

echo "==> Copying local environment and configuration files from root repo..."
for rel_path in \
  ".env" \
  "backend/.env" \
  ".claude/settings.local.json" \
  "escape_plan/BackendConfig.local.json"
do
  if [ -f "$ROOT_PATH/$rel_path" ] && [ ! -f "$rel_path" ]; then
    mkdir -p "$(dirname "$rel_path")"
    cp "$ROOT_PATH/$rel_path" "$rel_path"
    echo "  Copied $rel_path"
  fi
done

echo "==> Setting up Python virtual environment in backend/.venv..."
PYTHON_BIN=""
for candidate in python3.13 python3.12 python3.11 python3; do
  if command -v "$candidate" >/dev/null 2>&1; then
    if "$candidate" -c 'import sys; raise SystemExit(0 if sys.version_info >= (3, 11) else 1)' 2>/dev/null; then
      PYTHON_BIN="$candidate"
      break
    fi
  fi
done

if [ -z "$PYTHON_BIN" ]; then
  echo "Error: Python 3.11+ is required (macOS system Python 3.9 is too old)." >&2
  exit 1
fi

if [ ! -x "backend/.venv/bin/python" ]; then
  "$PYTHON_BIN" -m venv backend/.venv
fi

backend/.venv/bin/pip install --quiet --upgrade pip
backend/.venv/bin/pip install --quiet -r backend/requirements-dev.txt
echo "  Backend dependencies installed ($(backend/.venv/bin/python --version))."
