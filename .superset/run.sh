#!/usr/bin/env bash
# Superset on-demand dev server script (launched via the Run button).
set -euo pipefail

# Load environment variables from .env and backend/.env if present
set -a
[ -f ".env" ] && source ".env"
[ -f "backend/.env" ] && source "backend/.env"
set +a

export BACKEND_BEARER_TOKEN="${BACKEND_BEARER_TOKEN:-dev-local-token}"
PORT="${PORT:-8000}"

if [ ! -x "backend/.venv/bin/uvicorn" ]; then
  echo "backend/.venv not found; running ./.superset/setup.sh first..."
  ./.superset/setup.sh
fi

cd backend
exec .venv/bin/uvicorn app.main:app --reload --port "$PORT"
