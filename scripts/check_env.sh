#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BACKEND_DIR="$ROOT_DIR/apps/backend"

cd "$BACKEND_DIR"

if [ -f ".env" ]; then
  set -a
  source .env
  set +a
fi

HOST="${BACKEND_HOST:-127.0.0.1}"
PORT="${BACKEND_PORT:-8000}"

echo "BACKEND_HOST=$HOST"
echo "BACKEND_PORT=$PORT"

REQUIRED_TOKEN_VARS=(LIVEKIT_URL LIVEKIT_API_KEY LIVEKIT_API_SECRET)
MISSING=()

for VAR_NAME in "${REQUIRED_TOKEN_VARS[@]}"; do
  if [ -z "${!VAR_NAME:-}" ]; then
    MISSING+=("$VAR_NAME")
  fi
done

if [ ${#MISSING[@]} -gt 0 ]; then
  echo ""
  echo "LiveKit token config is incomplete. /livekit/token will return a structured config error."
  echo "Missing: ${MISSING[*]}"
  exit 0
fi

echo ""
echo "LiveKit token config is complete. /livekit/token can mint tokens."
