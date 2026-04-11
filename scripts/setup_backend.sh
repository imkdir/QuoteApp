#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BACKEND_DIR="$ROOT_DIR/apps/backend"
ENV_FILE="$BACKEND_DIR/.env"
EXAMPLE_ENV_FILE="$BACKEND_DIR/.env.example"

cd "$BACKEND_DIR"

PYTHON_BIN="${PYTHON_BIN:-python3}"

echo "QuoteApp backend setup"
echo "Backend directory: $BACKEND_DIR"
echo "Python binary: $PYTHON_BIN"

if ! "$PYTHON_BIN" -c 'import sys; raise SystemExit(0 if sys.version_info >= (3, 11) else 1)'; then
  echo ""
  echo "Warning: $PYTHON_BIN is below Python 3.11."
  echo "Continuing setup for compatibility mode; Python 3.11+ is still recommended."
fi

if [ ! -d ".venv" ]; then
  echo "Creating virtual environment (.venv)..."
  "$PYTHON_BIN" -m venv .venv
else
  echo "Virtual environment already exists (.venv)."
fi

# shellcheck disable=SC1091
source .venv/bin/activate

echo "Installing backend dependencies..."
python -m pip install --upgrade pip
pip install -r requirements.txt

if [ ! -f "$ENV_FILE" ] && [ -f "$EXAMPLE_ENV_FILE" ]; then
  cp "$EXAMPLE_ENV_FILE" "$ENV_FILE"
  echo ""
  echo "Created apps/backend/.env from .env.example."
  echo "Update apps/backend/.env with your LiveKit and TTS credentials."
fi

echo ""
echo "Running environment check..."
if ! "$ROOT_DIR/scripts/check_env.sh"; then
  echo ""
  echo "Setup finished, but environment is incomplete for full end-to-end runs."
  echo "Fill apps/backend/.env and rerun ./scripts/check_env.sh."
  exit 0
fi

echo ""
echo "Backend setup complete and environment looks ready."
