#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BACKEND_DIR="$ROOT_DIR/apps/backend"

cd "$BACKEND_DIR"

if [ ! -d ".venv" ]; then
  echo "Missing virtual environment. Run ./scripts/setup_backend.sh first."
  exit 1
fi

source .venv/bin/activate

if [ -f ".env" ]; then
  set -a
  source .env
  set +a
fi

HOST="${BACKEND_HOST:-127.0.0.1}"
PORT="${BACKEND_PORT:-8000}"

exec python -m uvicorn app.main:app --host "$HOST" --port "$PORT" --reload
